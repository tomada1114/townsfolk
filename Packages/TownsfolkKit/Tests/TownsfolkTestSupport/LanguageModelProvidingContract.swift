import FoundationModels
import Testing
import TownsfolkCore

/// The contract's own small output type: what ``LanguageModelProvidingContract`` asks a
/// provider to generate, and what a test scripts the fake to answer with.
@Generable
package struct ContractReply: Equatable {
    @Guide(description: "One short sentence.")
    package var text: String

    package init(text: String) {
        self.text = text
    }
}

/// The promises ``TownsfolkCore/LanguageModelProviding`` makes, checked against any
/// implementation of it (`.claude/rules/testing.md` › One Contract Suite per Port).
///
/// `TownsfolkCoreTests` runs ``check(_:)`` against ``FakeLanguageModelProvider`` on every
/// `just test` and in CI; `TownsfolkPlatformTests` runs it against
/// `SystemLanguageModelProvider` under `.requiresLocalMachine` (`just test-local`). Every
/// clause is one the port's `///` states; a new clause is stated there first.
package enum LanguageModelProvidingContract {
    /// The instructions every call the contract makes carries.
    package static let instructions = "Reply with one short sentence."
    /// The prompt the reply clause sends, and the base the token clauses extend.
    package static let prompt = "Say good morning to the town."
    /// What the token clause appends to ``prompt``.
    static let promptExtension = " Then say what the weather is like."
    /// What the overflow clause repeats until the prompt counts above the context size.
    static let overflowUnit = "The baker sings by the river. "
    /// How many times the overflow clause doubles its prompt before giving up. It starts
    /// at one unit (several tokens) per token of context, so the first prompt already
    /// overflows any tokenizer that counts a word as at least a token; three doublings
    /// reach eight units per token.
    static let overflowDoublings = 3

    /// A description of every broken promise, empty when `provider` keeps them all.
    ///
    /// Separate from ``check(_:)`` so a test can hand it a provider that breaks a promise
    /// and see the contract notice — the proof it is not vacuous.
    package static func violations(of provider: some LanguageModelProviding) async -> [String] {
        var broken: [String] = []
        let first = provider.availability
        let second = provider.availability
        if first != second {
            broken
                .append("availability answered \(first), then \(second), when asked twice in a row")
        }
        // Every other promise is made only while the model is available.
        guard first == .available, second == .available else {
            return broken
        }
        let contextSize = provider.contextSize
        if contextSize <= 0 {
            broken.append("contextSize is \(contextSize) while available")
        }
        broken += await tokenCountViolations(of: provider)
        broken += await replyViolations(of: provider)
        broken += await overflowViolations(of: provider, contextSize: contextSize)
        return broken
    }

    /// Records an issue for every promise `provider` breaks.
    package static func check(_ provider: some LanguageModelProviding) async {
        let broken = await violations(of: provider)
        #expect(
            broken.isEmpty,
            "\(type(of: provider)) breaks the LanguageModelProviding contract: \(broken)",
        )
    }

    private static func tokenCountViolations(
        of provider: some LanguageModelProviding,
    ) async -> [String] {
        var broken: [String] = []
        do {
            let empty = try await provider.tokenCount(instructions: "", prompt: "")
            if empty < 0 {
                broken.append("counting empty instructions and prompt answered \(empty)")
            }
        } catch {
            broken.append("counting empty instructions and prompt threw \(error)")
        }
        do {
            let base = try await provider.tokenCount(instructions: instructions, prompt: prompt)
            let extended = try await provider.tokenCount(
                instructions: instructions,
                prompt: prompt + promptExtension,
            )
            if try await provider.tokenCount(instructions: "", prompt: prompt) <= 0 {
                broken.append("a non-empty prompt counted 0 tokens")
            }
            if extended < base {
                broken
                    .append(
                        "an extended prompt counted fewer tokens (\(extended)) than its base (\(base))",
                    )
            }
        } catch {
            broken.append("counting a prompt threw \(error)")
        }
        return broken
    }

    private static func replyViolations(
        of provider: some LanguageModelProviding,
    ) async -> [String] {
        let content: GeneratedContent
        do {
            content = try await provider.respond(
                instructions: instructions,
                prompt: prompt,
                schema: ContractReply.generationSchema,
            )
        } catch {
            return ["respond within the context size threw \(error)"]
        }
        guard (try? ContractReply(content)) != nil else {
            return ["respond returned content that does not decode into ContractReply"]
        }
        return []
    }

    private static func overflowViolations(
        of provider: some LanguageModelProviding,
        contextSize: Int,
    ) async -> [String] {
        let overflowing: String
        do {
            guard let found = try await overflowingPrompt(for: provider, contextSize: contextSize)
            else {
                return [
                    "no prompt counted above the context size (\(contextSize)) after \(overflowDoublings) doublings",
                ]
            }
            overflowing = found
        } catch {
            return ["counting a long prompt threw \(error)"]
        }
        do {
            _ = try await provider.respond(
                instructions: instructions,
                prompt: overflowing,
                schema: ContractReply.generationSchema,
            )
            return ["respond over the context size returned content"]
        } catch ModelCallError.contextSizeExceeded {
            return []
        } catch {
            return ["respond over the context size threw \(error), not contextSizeExceeded"]
        }
    }

    /// A prompt `provider` counts, with the contract's instructions, above `contextSize`
    /// tokens, or `nil` when doubling never gets there.
    private static func overflowingPrompt(
        for provider: some LanguageModelProviding,
        contextSize: Int,
    ) async throws -> String? {
        var units = max(contextSize, 1)
        for _ in 0 ... overflowDoublings {
            let candidate = String(repeating: overflowUnit, count: units)
            let tokens = try await provider.tokenCount(
                instructions: instructions,
                prompt: candidate,
            )
            if tokens > contextSize {
                return candidate
            }
            units += units
        }
        return nil
    }
}
