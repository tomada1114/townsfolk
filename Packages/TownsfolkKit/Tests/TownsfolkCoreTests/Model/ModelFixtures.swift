import FoundationModels
import TownsfolkCore
import TownsfolkTestSupport

/// The values the model suites share.
enum ModelFixtures {
    /// The context size Apple documents for the on-device model, which the fakes default to.
    static let documentedContextSize = 4_096
    /// The context size reported, unverified, for macOS 27.
    static let reportedContextSize = 8_192
    /// A context size small enough that the contract's reply only just fits.
    static let smallContextSize = 128
    /// Context sizes the contract is run at: small, Apple's documented one, and the size
    /// reported for macOS 27.
    static let contractContextSizes = [smallContextSize, documentedContextSize, reportedContextSize]

    static let reply = ContractReply(text: "Morning.")
    static let instructions = "Write one post."
    static let prompt = "Mika and Jun talk."
    /// A string no error or description may contain: it stands for what the person or the
    /// model wrote.
    static let sentinel = "SENTINEL-prompt-text-4f1c"

    static var replyContent: GeneratedContent {
        reply.generatedContent
    }

    /// An available fake with the documented context size and one reply queued.
    static func fake() -> FakeLanguageModelProvider {
        fake(contextSize: documentedContextSize)
    }

    /// An available fake with `contextSize` tokens and one reply queued.
    static func fake(contextSize: Int) -> FakeLanguageModelProvider {
        FakeLanguageModelProvider(
            availability: .available,
            contextSize: contextSize,
            outcomes: [.content(replyContent)],
            holdsResponses: false,
        )
    }

    /// An available fake with the documented context size and `outcomes` queued.
    static func fake(outcomes: [FakeLanguageModelProvider.Outcome]) -> FakeLanguageModelProvider {
        FakeLanguageModelProvider(
            availability: .available,
            contextSize: documentedContextSize,
            outcomes: outcomes,
            holdsResponses: false,
        )
    }

    /// As ``fake(outcomes:)``, but every call is held until the test releases it.
    static func heldFake(
        outcomes: [FakeLanguageModelProvider.Outcome],
    ) -> FakeLanguageModelProvider {
        FakeLanguageModelProvider(
            availability: .available,
            contextSize: documentedContextSize,
            outcomes: outcomes,
            holdsResponses: true,
        )
    }

    /// A fake answering `availability`, with nothing queued.
    static func fake(
        availability: ModelAvailability,
        contextSize: Int,
    ) -> FakeLanguageModelProvider {
        FakeLanguageModelProvider(
            availability: availability,
            contextSize: contextSize,
            outcomes: [],
            holdsResponses: false,
        )
    }
}
