import FoundationModels
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// Error scripts are independent of response outcomes and preserve cancellation.
@Suite("FakeLanguageModelProvider failure scripts")
struct FakeLanguageModelFailureTests {
    private enum UnexpectedFailure: Error, Equatable {
        case scripted
    }

    @Test(arguments: [ModelCallError.unavailable, .other, .refused, .contextSizeExceeded])
    func `token counting throws queued model failures then resumes counting`(
        failure: ModelCallError,
    ) throws {
        let fake = FakeLanguageModelProvider(
            availability: .available,
            contextSize: 100,
            outcomes: [.content(ModelFixtures.replyContent)],
            holdsResponses: false,
            tokenCountFailures: [failure],
        )

        #expect(throws: failure) {
            try fake.tokenCount(instructions: "ab", prompt: "c")
        }
        #expect(try fake.tokenCount(instructions: "ab", prompt: "c") == 3)
        #expect(fake.calls.isEmpty)
    }

    @Test
    func `token counting throws an arbitrary error unchanged`() {
        let fake = FakeLanguageModelProvider(
            availability: .available,
            contextSize: 100,
            outcomes: [],
            holdsResponses: false,
            tokenCountFailures: [UnexpectedFailure.scripted],
        )

        #expect(throws: UnexpectedFailure.scripted) {
            try fake.tokenCount(instructions: "", prompt: "a")
        }
    }

    @Test
    func `respond throws an arbitrary error and consumes only that outcome`() async throws {
        let fake = ModelFixtures.fake(outcomes: [
            .unexpectedFailure(UnexpectedFailure.scripted),
            .content(ModelFixtures.replyContent),
        ])

        await #expect(throws: UnexpectedFailure.scripted) {
            try await fake.respond(
                instructions: "",
                prompt: "a",
                schema: ContractReply.generationSchema,
            )
        }
        let content = try await fake.respond(
            instructions: "",
            prompt: "b",
            schema: ContractReply.generationSchema,
        )
        #expect(try ContractReply(content) == ModelFixtures.reply)
        #expect(fake.calls.count == 2)
        #expect(fake.inFlightCount == 0)
    }

    @Test
    func `a cancelled token count leaves its failure queued`() async {
        let fake = FakeLanguageModelProvider(
            availability: .available,
            contextSize: 100,
            outcomes: [],
            holdsResponses: false,
            tokenCountFailures: [ModelCallError.unavailable, UnexpectedFailure.scripted],
        )
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try fake.tokenCount(instructions: "", prompt: "a")
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(throws: ModelCallError.unavailable) {
            try fake.tokenCount(instructions: "", prompt: "a")
        }
        #expect(throws: UnexpectedFailure.scripted) {
            try fake.tokenCount(instructions: "", prompt: "a")
        }
    }

    @Test
    func `respond does not consume token count failures`() async throws {
        let fake = FakeLanguageModelProvider(
            availability: .available,
            contextSize: 100,
            outcomes: [.content(ModelFixtures.replyContent)],
            holdsResponses: false,
            tokenCountFailures: [ModelCallError.other],
        )

        let content = try await fake.respond(
            instructions: "",
            prompt: "a",
            schema: ContractReply.generationSchema,
        )
        #expect(try ContractReply(content) == ModelFixtures.reply)
        #expect(throws: ModelCallError.other) {
            try fake.tokenCount(instructions: "", prompt: "a")
        }
    }
}
