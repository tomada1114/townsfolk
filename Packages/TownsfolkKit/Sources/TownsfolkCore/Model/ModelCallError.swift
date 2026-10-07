/// Why a model call returned nothing usable — the engine recovers differently from each
/// case, which is why this is an enum and not a message string.
///
/// No case carries a prompt, instructions, or anything the model wrote: an error travels
/// into logs and test output, and the town's text never leaves the conversation
/// (`designing-errors` › No user data in errors or logs). Not `LanguageModelError`, the
/// name the macOS 27 SDK already declares in `FoundationModels`, which Core imports.
public enum ModelCallError: Error, Equatable, Sendable {
    /// The instructions and prompt did not fit the context; the engine retries once with
    /// fewer posts.
    case contextSizeExceeded
    /// Any other failure; the app has no recovery for it beyond skipping the turn.
    case other
    /// A guardrail violation or a refusal; the engine retries with a new seed.
    case refused
    /// The model stopped being available — its assets went missing mid-call; the town rests
    /// until availability says it is back.
    case unavailable
}
