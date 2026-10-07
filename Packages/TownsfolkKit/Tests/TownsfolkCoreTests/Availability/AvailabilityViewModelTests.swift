import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// The shared fake port, answering `availability`; the view model only ever asks
/// whether the model can be called.
private func fakeProvider(_ availability: ModelAvailability) -> FakeLanguageModelProvider {
    let provider = ModelFixtures.fake()
    provider.availability = availability
    return provider
}

@MainActor
@Suite("AvailabilityViewModel")
struct AvailabilityViewModelTests {
    @Test(arguments: [
        ModelAvailability.available,
        .appleIntelligenceOff,
        .modelNotReady,
        .deviceNotEligible,
    ])
    func `the state is the port's answer when the model is created`(
        availability: ModelAvailability,
    ) {
        let model = AvailabilityViewModel(provider: fakeProvider(availability))
        #expect(model.availability == availability)
    }

    @Test
    func `available shows no message and no action`() {
        let model = AvailabilityViewModel(provider: fakeProvider(.available))
        #expect(!model.isUnavailable)
        #expect(model.notice == nil)
    }

    @Test
    func `with Apple Intelligence off the message names the pane and offers to open System Settings`(
    ) throws {
        let model = AvailabilityViewModel(provider: fakeProvider(.appleIntelligenceOff))
        #expect(model.isUnavailable)
        let notice = try #require(model.notice)
        let message = notice.message
        #expect(message.key == "availability.appleIntelligenceOff.message")
        #expect(message.resolved(in: .english) == """
        Townsfolk needs Apple Intelligence to write the town. \
        Turn it on in System Settings › Apple Intelligence & Siri.
        """)
        let action = try #require(notice.action)
        #expect(action.title.key == "availability.openSystemSettings")
        #expect(action.title.resolved(in: .english) == "Open System Settings")
        #expect(action.url == AvailabilityNotice.systemSettingsURL)
    }

    @Test
    func `the System Settings target is the app itself, as a file URL`() {
        #expect(
            AvailabilityNotice.systemSettingsURL.absoluteString
                == "file:///System/Applications/System%20Settings.app",
        )
    }

    @Test
    func `model not ready says it is downloading and offers no action`() throws {
        let model = AvailabilityViewModel(provider: fakeProvider(.modelNotReady))
        let notice = try #require(model.notice)
        let message = notice.message
        #expect(message.key == "availability.modelNotReady.message")
        #expect(message.resolved(in: .english)
            == "The on-device model is still downloading. The town starts when it's ready.")
        #expect(notice.action == nil)
    }

    @Test
    func `device not eligible says so and offers no action`() throws {
        let model = AvailabilityViewModel(provider: fakeProvider(.deviceNotEligible))
        let notice = try #require(model.notice)
        let message = notice.message
        #expect(message.key == "availability.deviceNotEligible.message")
        #expect(message.resolved(in: .english)
            == "This Mac can't run Apple Intelligence, which Townsfolk needs.")
        #expect(notice.action == nil)
    }

    @Test
    func `refresh asks the port again and follows a changed answer`() {
        let provider = fakeProvider(.available)
        let model = AvailabilityViewModel(provider: provider)
        provider.availability = .appleIntelligenceOff
        model.refresh()
        #expect(model.availability == .appleIntelligenceOff)
        #expect(model.notice?.action != nil)
    }

    @Test
    func `refresh from model not ready to available clears the message on that call`() {
        let provider = fakeProvider(.modelNotReady)
        let model = AvailabilityViewModel(provider: provider)
        #expect(model.notice != nil)
        provider.availability = .available
        model.refresh()
        #expect(model.availability == .available)
        #expect(!model.isUnavailable)
        #expect(model.notice == nil)
    }

    @Test
    func `the later of two refreshes wins`() {
        let provider = fakeProvider(.available)
        let model = AvailabilityViewModel(provider: provider)
        provider.availability = .modelNotReady
        model.refresh()
        provider.availability = .deviceNotEligible
        model.refresh()
        #expect(model.availability == .deviceNotEligible)
    }

    @Test
    func `a refresh with an unchanged answer leaves the state as it was`() {
        let provider = fakeProvider(.modelNotReady)
        let model = AvailabilityViewModel(provider: provider)
        model.refresh()
        #expect(model.availability == .modelNotReady)
    }
}
