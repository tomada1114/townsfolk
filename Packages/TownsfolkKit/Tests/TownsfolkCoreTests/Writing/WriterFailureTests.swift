import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// Failures other than a refusal or an overflow skip the turn and retry nothing
/// (REQ-012); no skip carries what anyone wrote (REQ-013); cancellation propagates
/// (REQ-014).
@Suite("SceneWriter failures")
struct WriterFailureTests {
    static func request(_ cast: WritingCast) throws -> SceneRequest {
        try cast.request(speakers: [cast.mika], seeds: [.topic("a"), .topic("b"), .topic("c")])
    }

    @Test(arguments: [
        ModelAvailability.appleIntelligenceOff,
        .deviceNotEligible,
        .modelNotReady,
    ])
    func `an unavailable model skips the turn without a call`(
        availability: ModelAvailability,
    ) async throws {
        try await withWritingStore { store, cast in
            let fake = WritingFixtures.fake([.content(WritingFixtures.mikaSpeaks)])
            fake.availability = availability
            let writer = SceneWriter(model: fake, store: store)

            let outcome = try await writer.write(Self.request(cast), at: WritingFixtures.now)

            #expect(outcome == .skipped(.unavailable))
            #expect(fake.calls.isEmpty)
        }
    }

    @Test(arguments: [
        (ModelCallError.unavailable, SceneSkipReason.unavailable),
        (.other, .modelFailed),
    ])
    func `a failed call skips the turn with its reason and retries nothing`(
        failure: ModelCallError,
        reason: SceneSkipReason,
    ) async throws {
        try await withWritingStore { store, cast in
            let fake = WritingFixtures.fake([
                .failure(failure),
                .content(WritingFixtures.mikaSpeaks),
            ])
            let writer = SceneWriter(model: fake, store: store)

            let outcome = try await writer.write(Self.request(cast), at: WritingFixtures.now)

            #expect(outcome == .skipped(reason))
            #expect(fake.calls.count == 1)
        }
    }

    @Test
    func `a failed store read skips the turn without a call`() async throws {
        try await withWritingStore { store, cast in
            try await store.deleteEverything()
            let fake = WritingFixtures.fake([.content(WritingFixtures.mikaSpeaks)])
            let writer = SceneWriter(model: fake, store: store)

            let outcome = try await writer.write(Self.request(cast), at: WritingFixtures.now)

            #expect(outcome == .skipped(.storeReadFailed(.closed)))
            #expect(fake.calls.isEmpty)
        }
    }

    @Test
    func `a skip carries nothing the model or you wrote`() async throws {
        try await withWritingStore { store, cast in
            let sentinel = ModelFixtures.sentinel
            let yours = try YourPostDraft(text: sentinel).make()
            try await store.storeYourPost(yours)
            let content = WritingFixtures.content([DraftPost(speaker: sentinel, text: sentinel)])
            let writer = SceneWriter(model: WritingFixtures.fake([.content(content)]), store: store)
            let request = try cast.request(
                speakers: [cast.mika],
                seeds: [.yourPost(yours, quoted: true, leadSpeaker: nil)],
            )

            let outcome = try await writer.write(request, at: WritingFixtures.now)

            #expect(outcome == .skipped(.invalidSpeaker))
            #expect(!String(describing: outcome).contains(sentinel))
        }
    }

    @Test
    func `cancelling the task during the call propagates CancellationError`() async throws {
        try await withWritingStore { store, cast in
            let fake = ModelFixtures.heldFake(outcomes: [.content(WritingFixtures.mikaSpeaks)])
            let writer = SceneWriter(model: fake, store: store)
            let request = try Self.request(cast)
            let task = Task {
                try await writer.write(request, at: WritingFixtures.now)
            }

            await fake.waitUntilHeld(count: 1)
            task.cancel()

            await #expect(throws: CancellationError.self) {
                try await task.value
            }
            #expect(fake.calls.count == 1)
        }
    }
}
