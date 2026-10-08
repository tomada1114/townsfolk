/// What the engine writes to ``AppLog/engine`` (REQ-011): each step's outcome and its
/// counts, and each event and move drawn, `.public` because they are states, kind ids, and
/// numbers. No post, name, tag, or description is ever in it — a skip reason, a dropped
/// event or move, and a store error carry only cases and codes (requirements §4).
enum EngineLog {
    static func recordResponsesScheduled(_ count: Int, offset: Double) {
        AppLog.engine
            .info(
                "responses scheduled: \(count, privacy: .public), first due in \(offset, privacy: .public) seconds",
            )
    }

    static func recordResponseStored(_ count: Int) {
        AppLog.engine.info("response stored: \(count, privacy: .public) posts")
    }

    /// Logs what one step did.
    static func record(_ outcome: EngineStep) {
        switch outcome {
        case .busy:
            AppLog.engine.debug("step: busy, another step is under way")

        case let .failed(error):
            AppLog.engine.error("step failed: \(String(describing: error), privacy: .public)")

        case .modelUnavailable:
            AppLog.engine.info("step: model unavailable, schedule unchanged")

        case .notFounded:
            AppLog.engine.debug("step: no town founded")

        case let .sceneStored(posts, _):
            AppLog.engine.info("step: scene stored, \(posts.count, privacy: .public) posts")

        case let .skipped(reason, _):
            AppLog.engine.info("step: skipped, \(String(describing: reason), privacy: .public)")

        case .waiting:
            AppLog.engine.debug("step: waiting, nothing due")
        }
    }

    /// Logs a due time measured again after a speed change.
    static func recordSpeedChange() {
        AppLog.engine.info("speed changed: next due time measured again")
    }

    /// Logs a speed change the store could not keep.
    static func recordSpeedChangeFailure(_ error: TownStoreError) {
        AppLog.engine.error(
            "speed change not stored: \(String(describing: error), privacy: .public)",
        )
    }

    /// Logs how many events ended at a turn.
    static func recordEventsEnded(_ count: Int) {
        AppLog.engine.info("events ended: \(count, privacy: .public)")
    }

    /// Logs an event started: its kind and how many hours it lasts.
    static func recordEventStarted(_ kind: EventKindID, hours: Int) {
        AppLog.engine.info(
            "event started: \(kind.rawValue, privacy: .public), \(hours, privacy: .public) hours",
        )
    }

    /// Logs a description refused for `kind`, which the next attempt draws away from.
    static func recordEventRefused(_ kind: EventKindID) {
        AppLog.engine.info("event description refused: \(kind.rawValue, privacy: .public)")
    }

    /// Logs a drawn event that starts nothing.
    static func recordEventDropped(_ reason: TownChangeDrop) {
        AppLog.engine.info("event dropped: \(String(describing: reason), privacy: .public)")
    }

    /// Logs a move stored, by its kind.
    static func recordMove(_ kind: EventKindID) {
        AppLog.engine.info("move stored: \(kind.rawValue, privacy: .public)")
    }

    /// Logs one newcomer attempt that failed, before the axes are drawn again.
    static func recordNewcomerFailed(_ reason: FoundingFailure) {
        AppLog.engine.info("newcomer attempt failed: \(reason.rawValue, privacy: .public)")
    }

    /// Logs a drawn move that moves nobody.
    static func recordMoveDropped(_ reason: TownChangeDrop) {
        AppLog.engine.info("move dropped: \(String(describing: reason), privacy: .public)")
    }

    /// Logs a written post ``Post`` refused, which turns the turn into a skip.
    static func recordRejectedPost(_ error: TownValueError) {
        AppLog.engine.error("written post refused: \(String(describing: error), privacy: .public)")
    }
}
