import Foundation

/// Keeps every uniqueness name and living relationship choice while shedding the oldest
/// past profiles. A prompt that still cannot fit is never sent to generation.
enum NewcomerPromptBudget {
    private struct Builder {
        let town: Town
        let seed: ResidentSeed
        let residents: [Resident]
        let past: [Resident.ID]

        func prompt(omitting count: Int) -> String {
            TownChangePrompts.newcomerPrompt(
                town: town,
                seed: seed,
                residents: residents,
                withoutPastProfiles: Set(past.prefix(count)),
            )
        }

        func fit(model: any LanguageModelProviding, budget: Int) async throws -> String? {
            func fits(_ prompt: String) async throws -> Bool {
                try await model.tokenCount(
                    instructions: TownChangePrompts.newcomerInstructions(), prompt: prompt,
                ) <= budget
            }
            let full = prompt(omitting: 0)
            if try await fits(full) {
                return full
            }
            var fittedPrompt = prompt(omitting: past.count)
            guard !past.isEmpty, try await fits(fittedPrompt) else {
                return nil
            }
            var overflowing = 0
            var fitting = past.count
            while fitting - overflowing > 1 {
                let middle = (fitting + overflowing) / NewcomerPromptBudget.bisectionDivisor
                let candidate = prompt(omitting: middle)
                if try await fits(candidate) {
                    fitting = middle
                    fittedPrompt = candidate
                } else {
                    overflowing = middle
                }
            }
            return fittedPrompt
        }
    }

    /// Divides the interval between a known overflowing and a known fitting prompt.
    private static let bisectionDivisor = 2

    static func fit(
        town: Town,
        seed: ResidentSeed,
        residents: [Resident],
        model: any LanguageModelProviding,
        tuning: Tuning,
    ) async throws -> FoundingAttempt<String> {
        let builder = Builder(
            town: town,
            seed: seed,
            residents: residents,
            past: residents.filter { $0.status == .movedOut }.sorted(by: older).map(\.id),
        )
        let budget = model.contextSize - tuning.generation.outputTokenReserve
        do {
            guard let prompt = try await builder.fit(model: model, budget: budget) else {
                return .failed(.overflow)
            }
            return .done(prompt)
        } catch let error as ModelCallError {
            return switch error {
            case .contextSizeExceeded:
                .failed(.overflow)

            case .other:
                .failed(.modelFailed)

            case .refused:
                .failed(.refused)

            case .unavailable:
                .unavailable
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            return .failed(.modelFailed)
        }
    }

    private static func older(_ first: Resident, _ second: Resident) -> Bool {
        (
            first.movedOutAt ?? .distantPast,
            first.movedInAt,
            first.name,
            first.id.rawValue.uuidString,
        )
            < (
                second.movedOutAt ?? .distantPast,
                second.movedInAt,
                second.name,
                second.id.rawValue.uuidString,
            )
    }
}
