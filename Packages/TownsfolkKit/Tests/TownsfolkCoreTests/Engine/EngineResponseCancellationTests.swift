import Foundation
import os
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// Cancels the task at the existing random schedule draw, before the real store hop.
private final class ResponseCancellation: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    var armed: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

private struct ResponseCancellingGenerator: RandomNumberGenerator, Sendable {
    let cancellation: ResponseCancellation

    func next() -> UInt64 {
        if cancellation.armed {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return 0
    }
}

@Suite("Town response preparation cancellation")
struct EngineResponseCancellationTests {
    @Test(arguments: [false, true])
    func `preparation cancellation propagates without a commit`(afterWriter: Bool) async throws {
        let cancellation = ResponseCancellation()
        var setup = try EngineSetup.mikaAlone()
        setup.generator = ResponseCancellingGenerator(cancellation: cancellation)
        setup.holdsResponses = afterWriter
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let engine = harness.engine
            let post = try EngineResponseFixtures.post()
            let raw = try harness.directory.raw()
            let before: [String: [String]]
            let stepping: Task<EngineStep, any Error>
            if afterWriter {
                stepping = Task { try await engine.step() }
                await harness.model.waitUntilHeld(count: 1)
                try await harness.store.storeYourPost(post)
                before = try raw.snapshot()
            } else {
                try await harness.store.storeYourPost(post)
                before = try raw.snapshot()
                stepping = Task {
                    cancellation.armed = true
                    return try await engine.step()
                }
            }
            cancellation.armed = true
            if afterWriter {
                harness.model.releaseHeld()
            }
            await #expect(throws: CancellationError.self) { try await stepping.value }
            #expect(try raw.snapshot() == before)
            #expect(try await harness.store.schedule()?.pendingResponses.isEmpty == true)
            #expect(try await harness.store.post(post.id) == post)
            #expect(harness.model.calls.count == (afterWriter ? 1 : 0))
        }
    }
}
