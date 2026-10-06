import TownsfolkCore

/// The presence values the presence suites share, outside their `@MainActor` suites so a
/// `@Test(arguments:)` list can read them.
enum PresenceFixtures {
    static let seen = WindowPresence(isWindowVisible: true, isAppActive: true, isMacAwake: true)
    static let covered = WindowPresence(isWindowVisible: false, isAppActive: true, isMacAwake: true)
    static let hidden = WindowPresence(isWindowVisible: false, isAppActive: false, isMacAwake: true)
    static let asleep = WindowPresence(
        isWindowVisible: false,
        isAppActive: false,
        isMacAwake: false,
    )
}
