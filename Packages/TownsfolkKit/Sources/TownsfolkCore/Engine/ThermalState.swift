/// How hot the Mac is running, as the engine reads it before a scene (requirements §3.11).
/// A Core enum, so the engine never sees `ProcessInfo`; the composition root maps the
/// system's thermal state into it (#27) and hands the engine a closure that reads it.
public enum ThermalState: Sendable, Equatable, CaseIterable {
    /// Hot enough to throttle: no scene is written.
    case critical
    /// Slightly warm.
    case fair
    /// Running cool.
    case nominal
    /// Hot: no scene is written (requirements.md:353).
    case serious

    /// Whether a scene may be written in this state: the town just seems quieter while the
    /// Mac is serious or critical.
    var allowsScenes: Bool {
        switch self {
        case .fair, .nominal:
            true

        case .critical, .serious:
            false
        }
    }
}
