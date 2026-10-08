import Foundation
import Testing
import TownsfolkCore

/// A fixed generation schema must agree with injected founding limits.
@Suite("TownDraft")
struct TownDraftTests {
    private static func invalidDraft(_ valid: TownDraft, breaking limit: String) -> TownDraft {
        var invalid = valid
        switch limit {
        case "name":
            invalid.name = String(repeating: "n", count: 36)

        case "too few places":
            invalid.places = []

        default:
            invalid.places = ["the bakery", "the river", "the station"]
        }
        return invalid
    }

    @Test
    func `the schema defers tunable limits and states immutable lengths`() throws {
        let encoded = try JSONEncoder().encode(TownDraft.generationSchema)
        let schema = try #require(String(bytes: encoded, encoding: .utf8))

        #expect(schema.contains("the character limit in the prompt"))
        #expect(schema.contains("The number of places requested in the prompt"))
        #expect(!schema.contains("3 to 5"))
        #expect(!schema.contains("minItems"))
        #expect(!schema.contains("maxItems"))
        #expect(schema.contains("at most \(Town.settingMaxLength) characters"))
        #expect(schema.contains("each at most \(Town.placeNameMaxLength) characters"))
    }

    @Test(arguments: [1, 2])
    func `custom founding limits reach the model and accept their boundaries`(
        placeCount: Int,
    ) async throws {
        try await withTownDirectory { directory in
            var tuning = Tuning.default
            tuning.founding.townNameMaxLength = 35
            tuning.founding.placeCount = 1 ... 2
            let store = try TownStore(directory: directory.town, tuning: tuning)
            let name = String(repeating: "n", count: 35)
            let places = Array(["the bakery", "the river"].prefix(placeCount))
            var answers = FoundingFixtures.happyPath
            answers[0] = .town(TownDraft(name: name, setting: "By a river.", places: places))
            let fake = FoundingFixtures.fake(answers)
            let founder = try Founder(
                model: fake,
                writer: SceneWriter(model: fake, store: store, tuning: tuning),
                seeds: FoundingFixtures.tables(),
                store: store,
                now: { FoundingFixtures.now },
                generator: FoundingFixtures.FirstChoice(),
                tuning: tuning,
            )

            #expect(try await found(with: founder) == .founded)
            let town = try #require(try await store.town())
            #expect(town.name == name)
            #expect(town.places == places)
            let call = try #require(fake.calls.first)
            #expect(call.instructions.contains("The name is at most 35 characters."))
            #expect(call.instructions.contains("There are 1 to 2 places"))
            #expect(fake.calls.count == 5)
        }
    }

    @Test(arguments: ["name", "too few places", "too many places"])
    func `custom founding limits reject an answer outside the boundary`(
        broken: String,
    ) async throws {
        try await withTownDirectory { directory in
            var tuning = Tuning.default
            tuning.founding.townNameMaxLength = 35
            tuning.founding.placeCount = 1 ... 2
            let store = try TownStore(directory: directory.town, tuning: tuning)
            let valid = TownDraft(name: "Maple", setting: "By a river.", places: ["the river"])
            let invalid = Self.invalidDraft(valid, breaking: broken)
            var answers = FoundingFixtures.happyPath
            answers[0] = .town(valid)
            let fake = FoundingFixtures.fake([.town(invalid)] + answers)
            let founder = try Founder(
                model: fake,
                writer: SceneWriter(model: fake, store: store, tuning: tuning),
                seeds: FoundingFixtures.tables(),
                store: store,
                now: { FoundingFixtures.now },
                generator: FoundingFixtures.FirstChoice(),
                tuning: tuning,
            )

            #expect(try await found(with: founder) == .founded)
            #expect(fake.calls.count == 6)
            let town = try #require(try await store.town())
            #expect(town.name == valid.name)
            #expect(town.places == valid.places)
        }
    }
}
