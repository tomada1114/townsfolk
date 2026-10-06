/// Whether the town window can be seen, as three facts Core can reason about.
///
/// The adapter behind ``WindowPresenceProviding`` reports these and nothing more: whether
/// the town runs — presence, the "keep moving" setting, and the model's availability — is
/// the engine's decision, made in Core where a test can drive it (ADR-0006).
public struct WindowPresence: Equatable, Hashable, Sendable {
    /// The town window has some part on screen: not minimized, hidden, on another Space,
    /// or completely covered, with the displays awake and this login session the active
    /// one. A sliver showing from under another window counts as visible (ADR-0006 ›
    /// Consequences).
    public var isWindowVisible: Bool
    /// This app is the active one, the app that receives key events.
    public var isAppActive: Bool
    /// The Mac is awake: `false` from the moment it announces it will sleep until it wakes.
    public var isMacAwake: Bool

    public init(isWindowVisible: Bool, isAppActive: Bool, isMacAwake: Bool) {
        self.isWindowVisible = isWindowVisible
        self.isAppActive = isAppActive
        self.isMacAwake = isMacAwake
    }
}
