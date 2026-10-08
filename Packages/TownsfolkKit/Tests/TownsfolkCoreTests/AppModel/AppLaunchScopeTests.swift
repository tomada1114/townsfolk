import Foundation
import Testing
import TownsfolkCore

@Suite("Launch test persistence isolation")
struct AppLaunchScopeTests {
    private static let testID = "11111111-2222-3333-4444-555555555555"
    private static let support = URL(filePath: "/application-support")
    private static let temporary = URL(filePath: "/temporary")

    @Test(arguments: [nil, "invalid", "../../Town"] as [String?])
    func `only a valid UUID selects test storage`(_ id: String?) {
        let scope = AppLaunchScope(testRunID: id)
        #expect(scope.settingsSuiteName == nil)
        #expect(scope.townDirectory(applicationSupport: Self.support, temporary: Self.temporary)
            == Self.support.appending(path: "Town"))
    }

    @Test
    func `nil settings suite reads the standard defaults domain`() throws {
        let separate = try #require(UserDefaults(suiteName: nil))
        #expect(separate !== UserDefaults.standard)
        let separateDomain = separate.dictionaryRepresentation()
        let standardDomain = UserDefaults.standard.dictionaryRepresentation()
        #expect(Set(separateDomain.keys) == Set(standardDomain.keys))
        #expect(separateDomain.allSatisfy { key, value in
            (value as? NSObject) == (standardDomain[key] as? NSObject)
        })
    }

    @Test
    func `a test gets its own settings suite and sandbox temporary store`() {
        let scope = AppLaunchScope(testRunID: Self.testID)
        #expect(scope.settingsSuiteName == "TownsfolkLaunchTests-\(Self.testID)")
        #expect(scope.townDirectory(applicationSupport: Self.support, temporary: Self.temporary)
            == Self.temporary.appending(path: "TownsfolkLaunchTests-\(Self.testID)/Town"))
    }
}
