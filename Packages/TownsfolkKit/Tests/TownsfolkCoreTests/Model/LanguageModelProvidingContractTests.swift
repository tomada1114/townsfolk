import FoundationModels
import os
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// Breaks the availability clause: it answers available and Apple Intelligence off in
/// turn.
private final class FlickeringProvider: LanguageModelProviding {
    private let reads = OSAllocatedUnfairLock(initialState: false)
    private let base = ModelFixtures.fake()

    var availability: ModelAvailability {
        reads.withLock { isOff in
            defer { isOff.toggle() }
            return isOff ? .appleIntelligenceOff : .available
        }
    }

    var contextSize: Int {
        base.contextSize
    }

    func tokenCount(instructions: String, prompt: String) throws -> Int {
        try base.tokenCount(instructions: instructions, prompt: prompt)
    }

    func respond(
        instructions: String,
        prompt: String,
        schema: GenerationSchema,
    ) async throws -> GeneratedContent {
        try await base.respond(instructions: instructions, prompt: prompt, schema: schema)
    }
}

/// The fake with one member replaced, so each oracle test breaks exactly one clause.
private struct TamperedProvider: LanguageModelProviding {
    typealias Count = @Sendable (_ instructions: String, _ prompt: String) throws -> Int
    typealias Respond = @Sendable (_ instructions: String, _ prompt: String) throws
        -> GeneratedContent

    private var base = ModelFixtures.fake()
    private var contextSizeOverride: Int?
    private var countOverride: Count?
    private var respondOverride: Respond?

    var availability: ModelAvailability {
        base.availability
    }

    var contextSize: Int {
        contextSizeOverride ?? base.contextSize
    }

    /// Answers `size` as its context size.
    static func sized(_ size: Int) -> Self {
        var provider = Self()
        provider.contextSizeOverride = size
        return provider
    }

    /// Counts tokens with `count`.
    static func counting(_ count: @escaping Count) -> Self {
        var provider = Self()
        provider.countOverride = count
        return provider
    }

    /// Replies with `respond`.
    static func replying(_ respond: @escaping Respond) -> Self {
        var provider = Self()
        provider.respondOverride = respond
        return provider
    }

    /// Answers everything from `base`, unchanged.
    static func wrapping(_ base: FakeLanguageModelProvider) -> Self {
        var provider = Self()
        provider.base = base
        return provider
    }

    func tokenCount(instructions: String, prompt: String) throws -> Int {
        if let countOverride {
            return try countOverride(instructions, prompt)
        }
        return try base.tokenCount(instructions: instructions, prompt: prompt)
    }

    func respond(
        instructions: String,
        prompt: String,
        schema: GenerationSchema,
    ) async throws -> GeneratedContent {
        if let respondOverride {
            return try respondOverride(instructions, prompt)
        }
        return try await base.respond(instructions: instructions, prompt: prompt, schema: schema)
    }
}

/// The fake half of the `LanguageModelProviding` contract suite: the same
/// ``LanguageModelProvidingContract`` that `TownsfolkPlatformTests` runs against
/// `SystemLanguageModelProvider` under `just test-local` runs here against
/// ``FakeLanguageModelProvider``, on every `just test` and in CI, so the fake cannot drift
/// from the port's promises.
@Suite("LanguageModelProviding contract, against the fake")
struct LanguageModelProvidingContractTests {
    @Test(arguments: ModelFixtures.contractContextSizes)
    func `the fake keeps the contract`(contextSize: Int) async {
        await LanguageModelProvidingContract.check(ModelFixtures.fake(contextSize: contextSize))
    }

    /// The clauses that need a working model are promised only while it is available, so
    /// an unavailable provider is held to the availability clause alone.
    @Test(arguments: [
        ModelAvailability.appleIntelligenceOff,
        .modelNotReady,
        .deviceNotEligible,
    ])
    func `an unavailable fake keeps the contract`(availability: ModelAvailability) async {
        let fake = ModelFixtures.fake(availability: availability, contextSize: 0)
        await LanguageModelProvidingContract.check(fake)
        #expect(fake.calls.isEmpty)
    }

    @Test
    func `the contract makes two calls, the second one over the context size`() async {
        let fake = ModelFixtures.fake(contextSize: 256)
        await LanguageModelProvidingContract.check(fake)

        #expect(fake.calls.count == 2)
        #expect(fake.calls.first?.prompt == LanguageModelProvidingContract.prompt)
        #expect((fake.calls.last?.prompt.count ?? 0) > 256)
    }

    // The contract's own oracle: a provider that breaks a clause must be reported, or
    // `check(_:)` would pass anything, the real adapter included.

    @Test
    func `availability that changes between two reads is reported`() async {
        let violations = await LanguageModelProvidingContract.violations(of: FlickeringProvider())
        #expect(violations == [
            "availability answered available, then appleIntelligenceOff, when asked twice in a row",
        ])
    }

    @Test(arguments: [0, -1])
    func `a context size that is not positive while available is reported`(size: Int) async {
        let violations = await LanguageModelProvidingContract.violations(
            of: TamperedProvider.sized(size),
        )
        #expect(violations.first == "contextSize is \(size) while available")
    }

    @Test
    func `a count that throws for empty text is reported`() async {
        let violations = await LanguageModelProvidingContract.violations(
            of: TamperedProvider.counting { instructions, prompt in
                guard !(instructions + prompt).isEmpty else {
                    throw ModelCallError.other
                }
                return instructions.count + prompt.count
            },
        )
        #expect(violations == ["counting empty instructions and prompt threw other"])
    }

    @Test
    func `a negative count for empty text is reported`() async {
        let violations = await LanguageModelProvidingContract.violations(
            of: TamperedProvider.counting { instructions, prompt in
                (instructions + prompt).isEmpty ? -1 : instructions.count + prompt.count
            },
        )
        #expect(violations == ["counting empty instructions and prompt answered -1"])
    }

    @Test
    func `a non-empty prompt counted as zero is reported`() async {
        let violations = await LanguageModelProvidingContract.violations(
            of: TamperedProvider.counting { _, _ in 0 },
        )
        #expect(violations.contains("a non-empty prompt counted 0 tokens"))
    }

    @Test
    func `a prompt that counts fewer once extended is reported`() async {
        let violations = await LanguageModelProvidingContract.violations(
            of: TamperedProvider.counting { _, prompt in max(1, 10_000 - prompt.count) },
        )
        #expect(violations.contains { $0.hasPrefix("an extended prompt counted fewer tokens") })
    }

    @Test
    func `a reply that does not decode into the contract's type is reported`() async {
        let violations = await LanguageModelProvidingContract.violations(
            of: TamperedProvider.replying { _, prompt in
                guard prompt == LanguageModelProvidingContract.prompt else {
                    throw ModelCallError.contextSizeExceeded
                }
                return GeneratedContent(properties: ["unrelated": 1])
            },
        )
        #expect(violations == ["respond returned content that does not decode into ContractReply"])
    }

    @Test
    func `a reply that throws is reported`() async {
        let violations = await LanguageModelProvidingContract.violations(
            of: TamperedProvider.wrapping(ModelFixtures.fake(outcomes: [.failure(.refused)])),
        )
        #expect(violations == ["respond within the context size threw refused"])
    }

    @Test
    func `an overflowing prompt that is answered anyway is reported`() async {
        let violations = await LanguageModelProvidingContract.violations(
            of: TamperedProvider.replying { _, _ in ModelFixtures.replyContent },
        )
        #expect(violations == ["respond over the context size returned content"])
    }

    @Test
    func `an overflowing prompt that throws another error is reported`() async {
        let violations = await LanguageModelProvidingContract.violations(
            of: TamperedProvider.replying { _, prompt in
                guard prompt == LanguageModelProvidingContract.prompt else {
                    throw ModelCallError.other
                }
                return ModelFixtures.replyContent
            },
        )
        #expect(violations == [
            "respond over the context size threw other, not contextSizeExceeded",
        ])
    }

    @Test
    func `a count that never exceeds the context size is reported`() async {
        let violations = await LanguageModelProvidingContract.violations(
            of: TamperedProvider.counting { _, prompt in min(prompt.count, 64) },
        )
        #expect(violations.contains { $0.hasPrefix("no prompt counted above the context size") })
    }
}
