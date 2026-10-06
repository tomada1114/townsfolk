import Testing
import TownsfolkCore

@Suite("DisplayName")
struct DisplayNameTests {
    @Test
    func `a name is trimmed at both ends`() throws {
        let name = try DisplayName("  Tomo  ")
        #expect(name.value == "Tomo")
    }

    @Test
    func `newlines at both ends are trimmed too`() throws {
        let name = try DisplayName("\n\tTomo\r\n")
        #expect(name.value == "Tomo")
    }

    @Test(arguments: [1, 20])
    func `a name at either edge of the default length is accepted`(length: Int) throws {
        let name = try DisplayName(TownFixtures.text(length))
        #expect(name.value.count == length)
    }

    @Test
    func `a name of 21 characters is too long`() {
        #expect(throws: TownValueError.tooLong(.displayName, limit: 20)) {
            try DisplayName(TownFixtures.text(21))
        }
    }

    @Test(arguments: ["", "   ", "\n\t "])
    func `a blank name is empty`(blank: String) {
        #expect(throws: TownValueError.empty(.displayName)) {
            try DisplayName(blank)
        }
    }

    @Test
    func `the limit is counted after trimming`() throws {
        let name = try DisplayName("  " + TownFixtures.text(20) + "  ")
        #expect(name.value.count == 20)
    }

    @Test
    func `a character is a grapheme cluster, not a scalar`() throws {
        let twenty = TownFixtures.text(20, of: TownFixtures.wavingHand)
        #expect(try DisplayName(twenty).value == twenty)
        let kana = TownFixtures.text(20, of: TownFixtures.hiragana)
        #expect(try DisplayName(kana).value == kana)
        #expect(throws: TownValueError.tooLong(.displayName, limit: 20)) {
            try DisplayName(twenty + TownFixtures.hiragana)
        }
    }

    @Test
    func `a smaller Tuning moves both edges`() throws {
        var tuning = Tuning.default
        tuning.founding.displayNameLength = 2 ... 4
        #expect(try DisplayName("ab", tuning: tuning).value == "ab")
        #expect(try DisplayName("abcd", tuning: tuning).value == "abcd")
        #expect(throws: TownValueError.tooShort(.displayName, minimum: 2)) {
            try DisplayName("a", tuning: tuning)
        }
        #expect(throws: TownValueError.tooLong(.displayName, limit: 4)) {
            try DisplayName("abcde", tuning: tuning)
        }
    }
}
