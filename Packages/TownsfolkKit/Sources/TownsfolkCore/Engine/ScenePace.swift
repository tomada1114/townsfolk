import Foundation

/// When things happen at a speed (requirements §3.2, §3.4): scene intervals with their
/// jitter, and the reveal times of a scene's posts. Every time it returns is whole
/// milliseconds, as the store keeps it, so a time the engine returns equals the one it
/// stored.
struct ScenePace {
    private static let millisecondsPerSecond = 1_000.0

    let tuning: Tuning

    /// `date` to the nearest millisecond.
    static func wholeMilliseconds(_ date: Date) -> Date {
        let milliseconds = (date.timeIntervalSince1970 * millisecondsPerSecond).rounded()
        return Date(timeIntervalSince1970: milliseconds / millisecondsPerSecond)
    }

    /// `seconds` to the nearest millisecond, as a duration a clock waits.
    static func duration(_ seconds: TimeInterval) -> Duration {
        .milliseconds(Int64((seconds * millisecondsPerSecond).rounded()))
    }

    /// One jitter draw: what a scene interval is multiplied by, uniform within
    /// `Tuning.pace.sceneIntervalJitter` either side of 1 (requirements.md:205).
    func drawFactor(using generator: inout some RandomNumberGenerator) -> Double {
        let jitter = max(0, tuning.pace.sceneIntervalJitter)
        return generator.nextFraction(in: (1 - jitter) ... (1 + jitter))
    }

    /// The scene interval at `speed`, multiplied by `factor`, in seconds.
    func interval(at speed: Speed, factor: Double) -> TimeInterval {
        tuning.pace.sceneInterval[speed] / .seconds(1) * factor
    }

    /// When the next scene is due: `factor` times the interval at `speed` after `anchor`.
    func due(after anchor: Date, speed: Speed, factor: Double) -> Date {
        Self.wholeMilliseconds(anchor.addingTimeInterval(interval(at: speed, factor: factor)))
    }

    /// When each of `count` posts appears: the first at `start`, each next one a
    /// `Tuning.timeline.revealSpacing` draw of the interval at `speed` later
    /// (requirements.md:167).
    func revealTimes(
        count: Int,
        from start: Date,
        speed: Speed,
        using generator: inout some RandomNumberGenerator,
    ) -> [Date] {
        var times = [Self.wholeMilliseconds(start)]
        var last = times[0]
        while times.count < count {
            let gap = generator.nextFraction(in: tuning.timeline.revealSpacing)
            last = Self.wholeMilliseconds(last.addingTimeInterval(interval(at: speed, factor: gap)))
            times.append(last)
        }
        return times
    }
}
