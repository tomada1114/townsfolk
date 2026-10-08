import Foundation

/// Which way a move goes.
enum MoveDirection: Equatable {
    /// A newcomer moves in.
    case moveIn
    /// A living resident moves away.
    case moveOut
}

/// Why a drawn event or move came to nothing. Logged `.public`, so no case carries a
/// description, a name, or anything the model wrote — only cases, codes, and counts
/// (`designing-errors` › No user data in errors or logs).
enum TownChangeDrop: Equatable {
    /// Every drawable kind is already ongoing.
    case everyKindOngoing
    /// The call failed for this reason, which a retry does not mend.
    case failed(FoundingFailure)
    /// The description, or the move's row, broke a rule of ``TownEvent`` or ``Resident``.
    case invalid(TownValueError)
    /// The model is unavailable.
    case modelUnavailable
    /// The seed tables hold an empty resident axis.
    case noAxes
    /// No town is founded yet to tell the model about.
    case notFounded
    /// The most events are already ongoing.
    case ongoingCap
    /// The population allows no move either way.
    case populationFixed
    /// Every attempt failed — refused calls, or newcomers out of bounds or repeating a name.
    case retriesSpent(attempts: Int)
    /// The store failed with this error, which carries only codes.
    case storeFailed(TownStoreError)
}

/// The rules that decide events and moves (requirements §3.6) — whether, which kind, how
/// long, and which way — never the model (`docs/architecture.md` › Principles). Pure, so
/// each takes the draw it needs or the generator to draw it with.
struct TownChangeRules {
    private static let secondsPerHour = 3_600.0

    let tuning: Tuning

    /// Seconds in `duration`.
    private static func seconds(_ duration: Duration) -> TimeInterval {
        duration / .seconds(1)
    }

    /// Which way a move goes among `living` residents, from a draw in `0 ..< 1`: in with
    /// chance (max − n) ÷ (max − min) of `Tuning.residents.population` — so always in at
    /// the minimum and out at the maximum — and never past either bound; `nil` when
    /// neither way stays within it (REQ-005).
    func direction(living: Int, roll: Double) -> MoveDirection? {
        let population = tuning.residents.population
        switch (living < population.upperBound, living > population.lowerBound) {
        case (false, false):
            return nil

        case (true, false):
            return .moveIn

        case (false, true):
            return .moveOut

        case (true, true):
            let room = Double(population.upperBound - living)
            let span = Double(population.upperBound - population.lowerBound)
            return roll < room / span ? .moveIn : .moveOut
        }
    }

    /// The chance a turn starts an event after `running` seconds of running time: running
    /// ÷ `Tuning.events.eventInterval` (requirements.md:254).
    func eventChance(running: TimeInterval) -> Double {
        running / Self.seconds(tuning.events.eventInterval)
    }

    /// How many whole hours an event of `kind` lasts: uniform within the kind's range,
    /// bounded by `Tuning.events.eventDuration` (requirements.md:255).
    func hours(
        of kind: SeedTables.EventKind,
        using generator: inout some RandomNumberGenerator,
    ) -> Int {
        let bounds = tuning.events.eventDuration
        let shortest = Int((Self.seconds(bounds.lowerBound) / Self.secondsPerHour).rounded(.up))
        let longest = max(
            shortest,
            Int((Self.seconds(bounds.upperBound) / Self.secondsPerHour).rounded(.down)),
        )
        let lower = min(max(kind.hours.lowerBound, shortest), longest)
        let upper = min(max(kind.hours.upperBound, shortest), longest)
        return lower + generator.nextIndex(below: upper - lower + 1)
    }

    /// When an event lasting `hours` from `start` ends.
    func end(after start: Date, hours: Int) -> Date {
        ScenePace.wholeMilliseconds(start.addingTimeInterval(Double(hours) * Self.secondsPerHour))
    }

    /// The chance a turn moves someone after `running` seconds of running time: running ÷
    /// d, with d drawn within `Tuning.residents.moveInterval` (requirements.md:258).
    func moveChance(
        running: TimeInterval,
        using generator: inout some RandomNumberGenerator,
    ) -> Double {
        let interval = tuning.residents.moveInterval
        let span = generator.nextFraction(
            in: Self.seconds(interval.lowerBound) ... Self.seconds(interval.upperBound),
        )
        return span > 0 ? running / span : 1
    }

    /// The running time a turn at `now` counts since `previous`, the turn before it in
    /// this run: none on the first turn, and at most the longest interval at `speed` —
    /// 1.5 × the scene interval — so time the engine was not running counts for nothing
    /// (requirements.md:254, :276).
    func runningTime(since previous: Date?, until now: Date, speed: Speed) -> TimeInterval {
        guard let previous else {
            return 0
        }
        let longest = ScenePace(tuning: tuning)
            .interval(at: speed, factor: 1 + max(0, tuning.pace.sceneIntervalJitter))
        return min(max(0, now.timeIntervalSince(previous)), longest)
    }
}
