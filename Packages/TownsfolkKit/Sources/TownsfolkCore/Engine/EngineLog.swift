/// What the engine writes to ``AppLog/engine`` (REQ-011): each step's outcome and its
/// counts, `.public` because they are states and numbers. No post, name, or tag is ever in
/// it — a skip reason and a store error carry only cases and codes (requirements §4).
enum EngineLog {
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

    /// Logs a written post ``Post`` refused, which turns the turn into a skip.
    static func recordRejectedPost(_ error: TownValueError) {
        AppLog.engine.error("written post refused: \(String(describing: error), privacy: .public)")
    }
}
