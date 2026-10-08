import Foundation
import TownsfolkCore

/// Opens a new store each time, recording only the number of openings.
@MainActor
final class AppSessionFactory {
    let directory: TownDirectory
    let defaults: UserDefaults
    let probe = AppRunProbe()
    private(set) var opens = 0

    init(directory: TownDirectory, defaults: UserDefaults) {
        self.directory = directory
        self.defaults = defaults
    }

    func open() throws -> AppTownSession {
        opens += 1
        return try AppHarness.session(
            store: TownStore(directory: directory.town),
            defaults: defaults,
            probe: probe,
        )
    }
}
