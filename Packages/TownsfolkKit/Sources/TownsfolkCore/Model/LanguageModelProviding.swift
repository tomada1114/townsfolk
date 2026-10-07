import FoundationModels

/// A port: the one call the town makes to a language model, and what it needs to know
/// before making it.
///
/// Core owns the conversation — the `@Generable` output types, the instructions and
/// prompts, the budget, and the retry rules (`docs/architecture.md` › The on-device
/// model); this port owns only the call. `TownsfolkPlatform`'s
/// `SystemLanguageModelProvider` answers it from Apple's on-device model, tests substitute
/// `FakeLanguageModelProvider`, and `App/` picks the real one.
///
/// Each member's `///` states its promises, each checked by
/// `LanguageModelProvidingContract` in `TownsfolkTestSupport` against the fake
/// (`just test`) and the real adapter (`just test-local`); a new clause is stated here
/// first, then added there. Every promise but the first is made only while
/// ``availability`` answers ``ModelAvailability/available``.
///
/// The members are not isolated to an actor: a call is long, and nothing about it is bound
/// to a run loop. Keeping calls one at a time is the engine's rule, not the port's.
public protocol LanguageModelProviding: Sendable {
    /// Whether the model can be called now.
    ///
    /// Promise: asked twice in a row, it answers the same case — it reports the state the
    /// model is in rather than deciding anything.
    var availability: ModelAvailability { get }

    /// How many tokens the instructions, the prompt, and the reply may use together, read
    /// from the model at run time rather than assumed.
    ///
    /// Promise: greater than 0 while available.
    var contextSize: Int { get }

    /// How many tokens `instructions` and `prompt` use together — what the budget is
    /// measured in. The generation schema's own tokens are not included.
    ///
    /// Promises, while available: empty instructions and an empty prompt count 0 or more
    /// without throwing; a non-empty prompt counts more than 0; and a prompt that extends
    /// another counts at least as many tokens as the one it extends.
    ///
    /// - Throws: ``ModelCallError``, or `CancellationError` when the calling task is
    ///   cancelled.
    func tokenCount(instructions: String, prompt: String) async throws -> Int

    /// One reply to `prompt` under `instructions`, generated under `schema` and returned
    /// as content Core decodes into the `@Generable` type the schema came from.
    ///
    /// Each call starts from nothing: no instructions, prompt, or reply from an earlier
    /// call is carried into it (§3.8, the log is the truth).
    ///
    /// Promises, while available: a reply under a `@Generable` type's schema decodes into
    /// that type; and instructions and a prompt that count above ``contextSize`` throw
    /// ``ModelCallError/contextSizeExceeded``.
    ///
    /// Plain `throws`, not `throws(ModelCallError)`: a cancelled call throws
    /// `CancellationError`, which a typed throw could not carry (`designing-errors` ›
    /// Typed throws or plain throws).
    ///
    /// - Throws: ``ModelCallError``, or `CancellationError` when the calling task is
    ///   cancelled; nothing else.
    func respond(
        instructions: String,
        prompt: String,
        schema: GenerationSchema,
    ) async throws -> GeneratedContent
}
