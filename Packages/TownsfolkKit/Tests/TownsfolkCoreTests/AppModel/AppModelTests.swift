import Foundation
import Testing
import TownsfolkCore

@Suite("App routing")
@MainActor
struct AppModelTests {
    @Test
    func `an unavailable first launch recovers to name entry with no restart`() async throws {
        try await withApp(availability: .appleIntelligenceOff) { app, _ in
            await app.model.open()
            #expect(app.model.route == .unavailable)
            app.provider.availability = .available
            await app.model.appActivityChanged(isActive: true)
            #expect(app.model.route == .firstRun)
            #expect(app.model.windowTitle == "Townsfolk")
        }
    }
}
