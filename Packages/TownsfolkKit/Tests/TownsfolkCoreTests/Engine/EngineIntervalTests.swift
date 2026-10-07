import Foundation
import Testing
import TownsfolkCore

/// Every drawn interval stays within ±50% of its speed's, the ends included
/// (requirements.md:205): all-zero draws reach the bottom, all-one draws the top, which
/// rounds to the millisecond of the end itself.
@Suite("Town engine intervals")
struct EngineIntervalTests {
    /// Each speed's interval bounds in seconds.
    static let bounds: [(Speed, ClosedRange<Double>)] = [
        (.fast, 30 ... 90),
        (.normal, 180 ... 540),
        (.slow, 900 ... 2_700),
    ]

    /// The due time a skipped hot turn draws at `speed` with `generator`, as seconds from
    /// now.
    static func drawnInterval(
        at speed: Speed,
        generator: any RandomNumberGenerator & Sendable,
    ) async throws -> Double {
        var setup = try EngineSetup.mikaAlone()
        setup.speed = speed
        setup.thermalState = .serious
        setup.generator = generator
        var interval = 0.0
        try await withEngine(setup) { harness in
            _ = try await harness.engine.step()
            interval = try await harness.storedDue().timeIntervalSince(EngineFixtures.start)
        }
        return interval
    }

    @Test(arguments: bounds)
    func `the lowest and highest draws reach the interval's ends`(
        speed: Speed,
        range: ClosedRange<Double>,
    ) async throws {
        let lowest = try await Self.drawnInterval(
            at: speed,
            generator: RepeatingGenerator(value: 0),
        )
        let highest = try await Self.drawnInterval(
            at: speed,
            generator: RepeatingGenerator(value: .max),
        )
        #expect(lowest == range.lowerBound)
        #expect(highest == range.upperBound)
    }

    @Test(arguments: bounds)
    func `seeded draws stay within the interval's bounds`(
        speed: Speed,
        range: ClosedRange<Double>,
    ) async throws {
        for seed: UInt64 in 0 ..< 20 {
            let interval = try await Self.drawnInterval(
                at: speed,
                generator: SplitMix64(seed: seed),
            )
            #expect(range.contains(interval), "seed \(seed): \(interval)")
        }
    }
}
