import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

@MainActor
@Suite("FrontmostAppViewModel")
struct FrontmostAppViewModelTests {
    @Test
    func `starts unavailable, before anything asks the port`() {
        let provider = FakeFrontmostAppProvider(answering: [FrontmostApp(name: "Finder")])
        let model = FrontmostAppViewModel(provider: provider)
        #expect(model.frontmostApp == nil)
        #expect(model.label.resolved(in: .english) == "Frontmost: —")
        #expect(provider.callCount == 0)
    }

    @Test
    func `refresh publishes what the port answered`() {
        let app = FrontmostApp(name: "Finder", bundleIdentifier: "com.apple.finder")
        let model = FrontmostAppViewModel(provider: FakeFrontmostAppProvider(answering: [app]))
        model.refresh()
        #expect(model.frontmostApp == app)
        #expect(model.label.resolved(in: .english) == "Frontmost: Finder")
    }

    @Test
    func `refresh reports unavailable when the port answers nil`() {
        let model = FrontmostAppViewModel(provider: FakeFrontmostAppProvider(answering: [nil]))
        model.refresh()
        #expect(model.frontmostApp == nil)
        #expect(model.label.resolved(in: .english) == "Frontmost: —")
    }

    @Test
    func `each refresh asks the port again and takes the newer answer`() {
        let provider = FakeFrontmostAppProvider(answering: [
            FrontmostApp(name: "Finder"),
            nil,
            FrontmostApp(name: "Terminal"),
        ])
        let model = FrontmostAppViewModel(provider: provider)
        model.refresh()
        #expect(model.label.resolved(in: .english) == "Frontmost: Finder")
        model.refresh()
        #expect(model.label.resolved(in: .english) == "Frontmost: —")
        model.refresh()
        #expect(model.label.resolved(in: .english) == "Frontmost: Terminal")
        #expect(provider.callCount == 3)
    }

    @Test
    func `a bundle identifier is carried through as a value`() {
        let app = FrontmostApp(name: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let model = FrontmostAppViewModel(provider: FakeFrontmostAppProvider(answering: [app]))
        model.refresh()
        #expect(model.frontmostApp?.bundleIdentifier == "com.apple.Terminal")
    }

    @Test
    func `a frontmost app without a bundle identifier is still a valid value`() {
        let app = FrontmostApp(name: "Some Helper")
        #expect(app.bundleIdentifier == nil)
        #expect(app == FrontmostApp(name: "Some Helper", bundleIdentifier: nil))
        #expect(app != FrontmostApp(name: "Some Helper", bundleIdentifier: "x"))
    }
}
