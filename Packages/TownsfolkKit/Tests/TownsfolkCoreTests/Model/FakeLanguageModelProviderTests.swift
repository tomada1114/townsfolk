import FoundationModels
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// The fake's own behavior beyond the contract: the scripted answers, the outcome queue,
/// the budget boundary, what it records, and cancellation — what the writer's tests (#14)
/// and the one-call-at-a-time test (#19) lean on.
@Suite("FakeLanguageModelProvider")
struct FakeLanguageModelProviderTests {
    @Test
    func `a scripted reply is returned, and the call is recorded`() async throws {
        let fake = ModelFixtures.fake()

        let content = try await fake.respond(
            instructions: ModelFixtures.instructions,
            prompt: ModelFixtures.prompt,
            schema: ContractReply.generationSchema,
        )

        #expect(try ContractReply(content) == ModelFixtures.reply)
        let expected = FakeLanguageModelProvider.Call(
            instructions: ModelFixtures.instructions,
            prompt: ModelFixtures.prompt,
        )
        #expect(fake.calls == [expected])
        #expect(fake.highestInFlight == 1)
        #expect(fake.inFlightCount == 0)
    }

    @Test
    func `outcomes are answered in order, one per call`() async throws {
        let second = ContractReply(text: "Evening.")
        let fake = ModelFixtures.fake(outcomes: [
            .content(ModelFixtures.replyContent),
            .content(second.generatedContent),
        ])

        let first = try await fake.respond(
            instructions: "",
            prompt: "one",
            schema: ContractReply.generationSchema,
        )
        let next = try await fake.respond(
            instructions: "",
            prompt: "two",
            schema: ContractReply.generationSchema,
        )

        #expect(try ContractReply(first) == ModelFixtures.reply)
        #expect(try ContractReply(next) == second)
        #expect(fake.calls.map(\.prompt) == ["one", "two"])
    }

    @Test(arguments: [
        ModelCallError.refused,
        .contextSizeExceeded,
        .unavailable,
        .other,
    ])
    func `a scripted failure is thrown as that case`(failure: ModelCallError) async {
        let fake = ModelFixtures.fake(outcomes: [.failure(failure)])

        await #expect(throws: failure) {
            try await fake.respond(
                instructions: "",
                prompt: "hello",
                schema: ContractReply.generationSchema,
            )
        }
        #expect(fake.calls.count == 1)
    }

    @Test
    func `when the outcomes run out, respond throws other`() async throws {
        let fake = ModelFixtures.fake(outcomes: [.content(ModelFixtures.replyContent)])
        _ = try await fake.respond(
            instructions: "",
            prompt: "first",
            schema: ContractReply.generationSchema,
        )

        await #expect(throws: ModelCallError.other) {
            try await fake.respond(
                instructions: "",
                prompt: "second",
                schema: ContractReply.generationSchema,
            )
        }
    }

    // MARK: - Tokens and the budget

    @Test(arguments: [
        (instructions: "", prompt: "", tokens: 0),
        (instructions: "ab", prompt: "", tokens: 2),
        (instructions: "", prompt: "abc", tokens: 3),
        (instructions: "Hi", prompt: " there", tokens: 8),
        // One Character each, however many scalars: "é" as e + combining acute, and a
        // thumbs-up with a skin tone.
        (instructions: "e\u{301}", prompt: "\u{1F44D}\u{1F3FD}", tokens: 2),
    ])
    func `tokens are one per Character of instructions and prompt`(
        instructions: String,
        prompt: String,
        tokens: Int,
    ) throws {
        let fake = ModelFixtures.fake()
        #expect(try fake.tokenCount(instructions: instructions, prompt: prompt) == tokens)
    }

    @Test
    func `a call exactly at the context size succeeds`() async throws {
        let fake = ModelFixtures.fake(contextSize: 10)

        let content = try await fake.respond(
            instructions: "1234",
            prompt: "567890",
            schema: ContractReply.generationSchema,
        )

        #expect(try ContractReply(content) == ModelFixtures.reply)
    }

    @Test
    func `one token over the context size throws, and leaves the outcome queued`() async throws {
        let fake = ModelFixtures.fake(contextSize: 10)

        await #expect(throws: ModelCallError.contextSizeExceeded) {
            try await fake.respond(
                instructions: "1234",
                prompt: "5678901",
                schema: ContractReply.generationSchema,
            )
        }
        let retried = try await fake.respond(
            instructions: "1234",
            prompt: "567",
            schema: ContractReply.generationSchema,
        )
        #expect(try ContractReply(retried) == ModelFixtures.reply)
        #expect(fake.calls.count == 2)
    }

    @Test
    func `a 4,097-character prompt overflows 4,096 tokens, and the error holds no text`() async {
        let fake = ModelFixtures.fake(contextSize: 4_096)
        let prompt = ModelFixtures.sentinel
            + String(repeating: "x", count: 4_097 - ModelFixtures.sentinel.count)
        #expect(prompt.count == 4_097)

        let error = await #expect(throws: ModelCallError.contextSizeExceeded) {
            try await fake.respond(
                instructions: "",
                prompt: prompt,
                schema: ContractReply.generationSchema,
            )
        }

        #expect(!String(describing: error).contains(ModelFixtures.sentinel))
        #expect(!String(reflecting: error).contains(ModelFixtures.sentinel))
    }

    // MARK: - Availability and context size

    @Test(arguments: [
        ModelAvailability.available,
        .appleIntelligenceOff,
        .modelNotReady,
        .deviceNotEligible,
    ])
    func `availability answers what was scripted`(availability: ModelAvailability) {
        let fake = ModelFixtures.fake(availability: availability, contextSize: 4_096)
        #expect(fake.availability == availability)
        #expect(fake.contextSize == 4_096)
    }

    @Test
    func `availability can change while the fake is in use`() {
        let fake = ModelFixtures.fake(availability: .modelNotReady, contextSize: 4_096)
        fake.availability = .available
        #expect(fake.availability == .available)
    }

    // MARK: - Overlap and cancellation

    @Test
    func `two calls started together are both in flight at once`() async throws {
        let fake = ModelFixtures.heldFake(outcomes: [
            .content(ModelFixtures.replyContent),
            .content(ModelFixtures.replyContent),
        ])

        async let first = fake.respond(
            instructions: "",
            prompt: "a",
            schema: ContractReply.generationSchema,
        )
        async let second = fake.respond(
            instructions: "",
            prompt: "b",
            schema: ContractReply.generationSchema,
        )
        await fake.waitUntilHeld(count: 2)
        #expect(fake.inFlightCount == 2)
        fake.releaseHeld()
        _ = try await (first, second)

        #expect(fake.highestInFlight == 2)
        #expect(fake.inFlightCount == 0)
    }

    @Test
    func `calls one after another never overlap`() async throws {
        let fake = ModelFixtures.fake(outcomes: [
            .content(ModelFixtures.replyContent),
            .content(ModelFixtures.replyContent),
        ])

        _ = try await fake.respond(
            instructions: "",
            prompt: "a",
            schema: ContractReply.generationSchema,
        )
        _ = try await fake.respond(
            instructions: "",
            prompt: "b",
            schema: ContractReply.generationSchema,
        )

        #expect(fake.highestInFlight == 1)
    }

    @Test
    func `a call from a cancelled task throws CancellationError and is not recorded`() async {
        let fake = ModelFixtures.fake()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fake.respond(
                instructions: "",
                prompt: "a",
                schema: ContractReply.generationSchema,
            )
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(fake.calls.isEmpty)
    }

    @Test
    func `a token count from a cancelled task throws CancellationError`() async {
        let fake = ModelFixtures.fake()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try fake.tokenCount(instructions: "", prompt: "a")
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test
    func `a call cancelled while in flight throws CancellationError`() async {
        let fake = ModelFixtures.heldFake(outcomes: [.content(ModelFixtures.replyContent)])
        let task = Task {
            try await fake.respond(
                instructions: "",
                prompt: "a",
                schema: ContractReply.generationSchema,
            )
        }
        await fake.waitUntilHeld(count: 1)

        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(fake.calls.count == 1)
        #expect(fake.inFlightCount == 0)
    }
}
