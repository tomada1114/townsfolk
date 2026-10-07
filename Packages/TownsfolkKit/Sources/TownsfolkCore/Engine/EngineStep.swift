import Foundation

/// Why a due turn wrote no scene. The engine stores a new due time and tries again on the
/// next turn (requirements.md:354).
///
/// No case carries a post, a name, or a tag: a reason is logged `.public`
/// (`designing-errors` › No user data in errors or logs).
public enum EngineSkipReason: Sendable, Equatable {
    /// The scene's request was refused — a rule of the engine's casting broke, which a
    /// test would have caught; the turn is skipped rather than trapping.
    case invalidRequest(SceneRequestError)
    /// The written scene could not be turned into stored posts.
    case invalidScene
    /// No display name is stored, so your posts could not be quoted under it.
    case noDisplayName
    /// No resident lives in town to speak.
    case noSpeakers
    /// The Mac reported this thermal state, serious or critical (requirements.md:353).
    case tooHot(ThermalState)
    /// The scene writer skipped the turn for this reason.
    case writer(SceneSkipReason)
}

/// What one ``TownEngine/step()`` did — at most one unit of work. `run()` decides how long
/// to wait from it.
public enum EngineStep: Sendable, Equatable {
    /// Another step was already under way, so this one did nothing (REQ-008).
    case busy
    /// The store failed; nothing of the step was kept (REQ-009). The error carries only
    /// codes.
    case failed(TownStoreError)
    /// The model is unavailable: nothing was called, and the schedule is unchanged, so the
    /// overdue scene runs once the model is back (REQ-007).
    case modelUnavailable
    /// No town is founded yet.
    case notFounded
    /// One scene was stored: its posts, in order, and when the next one is due.
    case sceneStored(posts: [Post.ID], nextDue: Date)
    /// The due turn was skipped; only the next due time was stored.
    case skipped(EngineSkipReason, nextDue: Date)
    /// No scene is due before this time.
    case waiting(until: Date)
}
