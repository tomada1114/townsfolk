import Foundation
import FoundationModels

/// What one attempt at a founding step came to.
enum FoundingAttempt<Value> {
    /// The step succeeded with this value.
    case done(Value)
    /// The attempt failed and counts against the run.
    case failed(FoundingFailure)
    /// The model is gone; founding ends without counting an attempt.
    case unavailable
}

extension LanguageModelProviding {
    /// One founding call under `Draft`'s schema, decoded: a refusal, a failure, an
    /// overflow, or an answer that does not decode is a failed attempt, and an
    /// unavailable model ends founding.
    /// - Throws: `CancellationError` when the calling task is cancelled, and nothing else.
    func foundingReply<Draft: Generable>(
        _: Draft.Type,
        instructions: String,
        prompt: String,
    ) async throws -> FoundingAttempt<Draft> {
        let content: GeneratedContent
        do {
            content = try await respond(
                instructions: instructions,
                prompt: prompt,
                schema: Draft.generationSchema,
            )
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
            // Beyond the port's promise; counted as a failed attempt rather than thrown.
            return .failed(.modelFailed)
        }
        do {
            return try .done(Draft(content))
        } catch {
            return .failed(.malformedOutput)
        }
    }

    /// Asks for the town the first residents' `seeds` live in, and checks the answer
    /// against the town's limits (REQ-002).
    func inventTown(
        from seeds: [ResidentSeed],
        foundedAt: Date,
        tuning: Tuning,
    ) async throws -> FoundingAttempt<Town> {
        let reply = try await foundingReply(
            TownDraft.self,
            instructions: FoundingPrompts.townInstructions(tuning: tuning),
            prompt: FoundingPrompts.townPrompt(seeds: seeds),
        )
        switch reply {
        case let .done(draft):
            do {
                return try .done(Town(
                    name: draft.name,
                    setting: draft.setting,
                    places: draft.places,
                    foundedAt: foundedAt,
                    tuning: tuning,
                ))
            } catch {
                return .failed(.invalidTown)
            }

        case let .failed(reason):
            return .failed(reason)

        case .unavailable:
            return .unavailable
        }
    }

    /// Asks for the resident seeded from `seed`, moving into `town` after `earlier`, and
    /// checks the answer (REQ-003).
    func inventResident(
        from seed: ResidentSeed,
        in town: Town,
        after earlier: [Resident],
        movedInAt: Date,
    ) async throws -> FoundingAttempt<Resident> {
        let reply = try await foundingReply(
            NewResidentDraft.self,
            instructions: FoundingPrompts.residentInstructions(),
            prompt: FoundingPrompts.residentPrompt(town: town, seed: seed, earlier: earlier),
        )
        switch reply {
        case let .done(draft):
            do throws(FoundingFailure) {
                return try .done(draft.resident(
                    id: Resident.ID(),
                    seed: seed,
                    among: earlier,
                    movedInAt: movedInAt,
                ))
            } catch {
                return .failed(error)
            }

        case let .failed(reason):
            return .failed(reason)

        case .unavailable:
            return .unavailable
        }
    }
}
