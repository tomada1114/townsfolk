import Foundation
import Testing
import TownsfolkCore

/// A resident's profile read from the store (REQ-001, REQ-006, ux-flows S4).
@MainActor
@Suite("Profile view model")
struct ProfileViewModelTests {
    /// Mika, who knows Jun and Sora, and Hana, who knows no one.
    private struct ProfileTown {
        let mika = Resident.ID()
        let jun = Resident.ID()
        let sora = Resident.ID()
        let hana = Resident.ID()
        let movedIn = StoreFixtures.date("2026-09-30T09:00:00Z")

        func profile() throws -> Resident.Profile {
            try Resident.Profile(
                ageGroup: "30s",
                occupation: "Baker",
                hobby: "Film photography",
                worry: "The oven is dying",
                personality: "Cheerful, a little stubborn",
            )
        }

        func mika(interests: [Interest.ID] = []) throws -> Resident {
            try Resident(
                id: mika,
                name: "Mika Tanaka",
                profile: profile(),
                movedInAt: movedIn,
                relationships: [
                    Resident.Relationship(resident: jun, description: "old friend"),
                    Resident.Relationship(resident: sora, description: "landlady"),
                ],
                interests: interests,
            )
        }

        func founding() throws -> TownStore.FoundingStep {
            let post = try ResidentPostDraft(author: jun, time: movedIn).make()
            return try TownStore.FoundingStep(
                town: TownsfolkCore.Town(
                    name: "Maplewood",
                    setting: "A small town by a slow river.",
                    places: ["the bakery", "the river", "the station"],
                    foundedAt: movedIn,
                ),
                residents: [
                    mika(),
                    ResidentDraft(name: "Jun", id: jun, movedInAt: movedIn).make(),
                    ResidentDraft(name: "Sora", id: sora, movedInAt: movedIn).make(),
                    ResidentDraft(name: "Hana", id: hana, movedInAt: movedIn).make(),
                ],
                foundingEvent: EventDraft(kind: .founding, time: movedIn).make(),
                schedule: Schedule(nextOrdinarySceneDue: movedIn, lastRanAt: movedIn),
                firstScene: TownStore.SceneStep(posts: [post]),
            )
        }

        /// Stores `interests` and gives Mika all of them.
        func takeUp(_ terms: [String], in store: TownStore) async throws -> [Interest] {
            let interests = try terms.map { try InterestDraft(term: $0, time: movedIn).make() }
            let post = try ResidentPostDraft(author: jun, time: movedIn).make()
            try await store.storeScene(TownStore.SceneStep(posts: [post], interests: interests))
            try await store.recordMove(TownStore.MoveStep(
                resident: mika(interests: interests.map(\.id)),
                event: EventDraft(time: movedIn).make(),
            ))
            return interests
        }
    }

    private static let english = Locale(identifier: "en_US_POSIX")

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let zone = TimeZone(identifier: "UTC") {
            calendar.timeZone = zone
        }
        return calendar
    }

    private static func text(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }

    private static func loaded(
        _ id: Resident.ID,
        from store: TownStore,
        locale: Locale = english,
    ) async -> ProfileViewModel {
        let model = ProfileViewModel(store: store, resident: id, locale: locale, calendar: utc)
        await model.load()
        return model
    }

    @Test
    func `a living resident's profile shows every field in the S4 layout`() async throws {
        let town = ProfileTown()
        try await withStore { store, _ in
            try await store.found(town.founding())
            _ = try await town.takeUp(["Rust"], in: store)
            let model = await Self.loaded(town.mika, from: store)
            let profile = try #require(model.profile)
            #expect(profile.name == "Mika Tanaka")
            #expect(!profile.isPastResident)
            #expect(Self.text(profile.summary) == "Baker · 30s")
            #expect(profile.personality == "Cheerful, a little stubborn")
            #expect(profile.hobby == "Film photography")
            #expect(profile.worry == "The oven is dying")
            #expect(profile.knows.map(Self.text) == ["Jun — old friend", "Sora — landlady"])
            #expect(profile.interests.map(Self.text) == ["Rust (from you)"])
            #expect(Self.text(profile.moveLine) == "Moved in Sep 30")
        }
    }

    @Test
    func `no relationships and no interests leave both rows empty`() async throws {
        let town = ProfileTown()
        try await withStore { store, _ in
            try await store.found(town.founding())
            let profile = try #require(await Self.loaded(town.hana, from: store).profile)
            #expect(profile.knows.isEmpty)
            #expect(profile.interests.isEmpty)
        }
    }

    @Test
    func `five interests are all listed, each from you`() async throws {
        let town = ProfileTown()
        try await withStore { store, _ in
            try await store.found(town.founding())
            let terms = ["Rust", "Go", "Kotlin", "Swift", "Elm"]
            _ = try await town.takeUp(terms, in: store)
            let profile = try #require(await Self.loaded(town.mika, from: store).profile)
            #expect(profile.interests.map(Self.text) == terms.map { "\($0) (from you)" })
        }
    }

    @Test
    func `an interest excluded from later contexts is not shown`() async throws {
        let town = ProfileTown()
        try await withStore { store, _ in
            try await store.found(town.founding())
            let interests = try await town.takeUp(["Rust", "Go"], in: store)
            try await store.excludeInterest(interests[0].id)
            let profile = try #require(await Self.loaded(town.mika, from: store).profile)
            #expect(profile.interests.map(Self.text) == ["Go (from you)"])
        }
    }

    @Test
    func `a past resident shows the day they moved out`() async throws {
        let town = ProfileTown()
        try await withStore { store, _ in
            try await store.found(town.founding())
            let hana = try Resident(
                id: town.hana,
                name: "Hana",
                profile: town.profile(),
                movedInAt: town.movedIn,
                status: .movedOut,
                movedOutAt: StoreFixtures.date("2026-10-12T09:00:00Z"),
            )
            try await store.recordMove(TownStore.MoveStep(
                resident: hana,
                event: EventDraft(kind: .moveOut, time: town.movedIn, relatedResident: town.hana)
                    .make(),
            ))
            let profile = try #require(await Self.loaded(town.hana, from: store).profile)
            #expect(profile.isPastResident)
            #expect(Self.text(profile.moveLine) == "Moved out Oct 12")
        }
    }

    @Test
    func `the date is written in the injected locale`() async throws {
        let town = ProfileTown()
        try await withStore { store, _ in
            try await store.found(town.founding())
            let french = Locale(identifier: "fr_FR")
            let profile = try #require(
                await Self.loaded(town.hana, from: store, locale: french).profile,
            )
            var style = Date.FormatStyle(
                locale: french,
                calendar: Self.utc,
                timeZone: Self.utc.timeZone,
            )
            .month(.abbreviated)
            .day()
            style.locale = french
            #expect(Self.text(profile.moveLine) == "Moved in \(town.movedIn.formatted(style))")
            #expect(Self.text(profile.moveLine) != "Moved in Sep 30")
        }
    }

    @Test
    func `a resident the store no longer holds has no profile`() async throws {
        try await withStore { store, _ in
            let model = await Self.loaded(Resident.ID(), from: store)
            #expect(model.profile == nil)
            #expect(model.hasLoaded)
        }
    }

    @Test
    func `a closed store reads as no profile`() async throws {
        let town = ProfileTown()
        try await withStore { store, _ in
            try await store.found(town.founding())
            try await store.deleteEverything()
            let model = await Self.loaded(town.mika, from: store)
            #expect(model.profile == nil)
            #expect(model.hasLoaded)
        }
    }

    @Test
    func `a model made from a profile shows it without loading`() throws {
        let town = ProfileTown()
        let profile = try ResidentProfile(
            resident: town.mika(),
            residents: [],
            interests: [],
            locale: Self.english,
            calendar: Self.utc,
        )
        let model = ProfileViewModel(profile: profile)
        #expect(model.profile == profile)
        #expect(model.hasLoaded)
        #expect(profile.knows.isEmpty)
    }

    @Test
    func `the row labels and menu title read as S4 and S8 write them`() {
        #expect(Self.text(ProfileViewModel.hobbyTitle) == "Hobby")
        #expect(Self.text(ProfileViewModel.worryTitle) == "Worry")
        #expect(Self.text(ProfileViewModel.knowsTitle) == "Knows")
        #expect(Self.text(ProfileViewModel.intoTitle) == "Into")
        #expect(Self.text(ProfileViewModel.showProfileTitle) == "Show Profile")
        #expect(Self.text(ProfileViewModel.nameButtonHint) == "Show profile")
    }
}
