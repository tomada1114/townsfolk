import Foundation

/// Selects persistence for an explicitly identified launch test. App reads this input
/// only in Debug builds; a valid UUID keeps the test's first launch separate from every
/// real town and from other tests. This value creates neither a store nor settings.
public struct AppLaunchScope: Sendable {
    private let testRunID: UUID?

    /// A unique settings suite, or `nil` for the normal standard defaults.
    public var settingsSuiteName: String? {
        testRunID.map { "TownsfolkLaunchTests-\($0.uuidString)" }
    }

    /// Validates the identifier; missing or malformed input uses normal app persistence.
    public init(testRunID: String? = nil) {
        self.testRunID = testRunID.flatMap(UUID.init(uuidString:))
    }

    /// Normal towns live in Application Support; a launch test gets its own app-owned
    /// temporary directory. UUID validation prevents an input from naming another path.
    public func townDirectory(applicationSupport: URL, temporary: URL) -> URL {
        if let testRunID {
            temporary.appending(path: "TownsfolkLaunchTests-\(testRunID.uuidString)/Town")
        } else {
            applicationSupport.appending(path: "Town")
        }
    }
}
