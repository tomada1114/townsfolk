import Testing
import TownsfolkCore

@Suite("Town")
struct TownTests {
    private static let places = ["the bakery", "the station", "Willow Park"]

    private func town(
        name: String = "Maplewood",
        setting: String = "A river town. The trains stop twice a day.",
        places: [String] = Self.places,
        tuning: Tuning = .default,
    ) throws(TownValueError) -> Town {
        try Town(
            name: name,
            setting: setting,
            places: places,
            foundedAt: TownFixtures.movedIn,
            language: .japanese,
            tuning: tuning,
        )
    }

    @Test
    func `a town keeps every field it was given, trimmed`() throws {
        let maplewood = try town(
            name: " Maplewood ",
            setting: " A river town. ",
            places: [" the bakery", "the station ", "Willow Park"],
        )
        #expect(maplewood.name == "Maplewood")
        #expect(maplewood.setting == "A river town.")
        #expect(maplewood.places == Self.places)
        #expect(maplewood.foundedAt == TownFixtures.movedIn)
        #expect(maplewood.language == .japanese)
    }

    // MARK: - Name

    @Test
    func `a name of 30 characters is accepted and 31 is too long`() throws {
        #expect(try town(name: TownFixtures.text(30)).name.count == 30)
        #expect(throws: TownValueError.tooLong(.townName, limit: 30)) {
            try town(name: TownFixtures.text(31))
        }
    }

    @Test
    func `a blank name is empty`() {
        #expect(throws: TownValueError.empty(.townName)) {
            try town(name: "")
        }
    }

    // MARK: - Setting

    @Test
    func `a setting of 400 characters is accepted and 401 is too long`() throws {
        #expect(try town(setting: TownFixtures.text(400)).setting.count == 400)
        #expect(throws: TownValueError.tooLong(.setting, limit: 400)) {
            try town(setting: TownFixtures.text(401))
        }
    }

    @Test
    func `a blank setting is empty`() {
        #expect(throws: TownValueError.empty(.setting)) {
            try town(setting: "\n")
        }
    }

    // MARK: - Places

    @Test(arguments: [3, 5])
    func `three to five places are accepted`(count: Int) throws {
        let named = (0 ..< count).map { "place \($0)" }
        #expect(try town(places: named).places == named)
    }

    @Test
    func `two places are too few`() {
        #expect(throws: TownValueError.tooFew(.places, minimum: 3)) {
            try town(places: ["a", "b"])
        }
    }

    @Test
    func `six places are too many`() {
        #expect(throws: TownValueError.tooMany(.places, limit: 5)) {
            try town(places: ["a", "b", "c", "d", "e", "f"])
        }
    }

    @Test
    func `a place name of 30 characters is accepted and 31 is too long`() throws {
        let thirty = TownFixtures.text(30)
        #expect(try town(places: [thirty, "b", "c"]).places.first == thirty)
        #expect(throws: TownValueError.tooLong(.place, limit: 30)) {
            try town(places: [TownFixtures.text(31), "b", "c"])
        }
    }

    @Test
    func `a blank place name is empty`() {
        #expect(throws: TownValueError.empty(.place)) {
            try town(places: ["a", " ", "c"])
        }
    }

    // MARK: - Tuning

    @Test
    func `a smaller Tuning moves the name and place limits`() throws {
        var tuning = Tuning.default
        tuning.founding.townNameMaxLength = 3
        tuning.founding.placeCount = 1 ... 2
        #expect(try town(name: "abc", places: ["a"], tuning: tuning).name == "abc")
        #expect(throws: TownValueError.tooLong(.townName, limit: 3)) {
            try town(name: "abcd", places: ["a"], tuning: tuning)
        }
        #expect(throws: TownValueError.tooMany(.places, limit: 2)) {
            try town(name: "abc", places: ["a", "b", "c"], tuning: tuning)
        }
    }
}
