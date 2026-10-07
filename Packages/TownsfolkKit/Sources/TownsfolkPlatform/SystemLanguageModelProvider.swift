import FoundationModels
import TownsfolkCore

/// The Foundation Models adapter for ``TownsfolkCore/LanguageModelProviding``: Apple's
/// on-device model, `SystemLanguageModel.default`, with its default guardrails.
///
/// Translation only. Every ``respond(instructions:prompt:schema:)`` opens a fresh
/// `LanguageModelSession` and drops it when the call returns, so nothing from one call
/// reaches the next — Core rebuilds every call from the store (§3.8). Availability, the
/// context size, and token counts are read from the model each time they are asked; what
/// the town does about them is Core's decision. ``SystemLanguageModelTranslation`` maps the
/// framework's answers and errors (`docs/architecture.md` › The on-device model lists each
/// case).
public struct SystemLanguageModelProvider: LanguageModelProviding {
    private let model: SystemLanguageModel

    public var availability: ModelAvailability {
        SystemLanguageModelTranslation.availability(of: model.availability)
    }

    public var contextSize: Int {
        model.contextSize
    }

    public init() {
        model = .default
    }

    public func tokenCount(instructions: String, prompt: String) async throws -> Int {
        do {
            let instructionTokens = try await model.tokenCount(for: Instructions(instructions))
            let promptTokens = try await model.tokenCount(for: prompt)
            return instructionTokens + promptTokens
        } catch {
            throw try SystemLanguageModelTranslation.callError(for: error, during: "tokenCount")
        }
    }

    public func respond(
        instructions: String,
        prompt: String,
        schema: GenerationSchema,
    ) async throws -> GeneratedContent {
        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            return try await session.respond(to: prompt, schema: schema).content
        } catch {
            throw try SystemLanguageModelTranslation.callError(for: error, during: "respond")
        }
    }
}
