import Testing
import TownsfolkCore

@Suite("YourPostText")
struct YourPostTextTests {
    @Test
    func `text is trimmed at both ends`() throws {
        let text = try YourPostText("  Learning Rust today.\n")
        #expect(text.value == "Learning Rust today.")
    }

    @Test(arguments: [1, 140])
    func `text at either edge of the default length is accepted`(length: Int) throws {
        let text = try YourPostText(TownFixtures.text(length))
        #expect(text.value.count == length)
    }

    @Test
    func `text of 141 characters is too long`() {
        #expect(throws: TownValueError.tooLong(.postText, limit: 140)) {
            try YourPostText(TownFixtures.text(141))
        }
    }

    @Test(arguments: ["", "   ", "\n"])
    func `blank text is empty`(blank: String) {
        #expect(throws: TownValueError.empty(.postText)) {
            try YourPostText(blank)
        }
    }

    @Test(arguments: ["first\nsecond", "first\r\nsecond", "first\u{2028}second"])
    func `an inner line break is rejected`(text: String) {
        #expect(throws: TownValueError.multipleLines(.postText)) {
            try YourPostText(text)
        }
    }

    @Test
    func `a line break outside the limit is still a line break, not a length`() {
        #expect(throws: TownValueError.multipleLines(.postText)) {
            try YourPostText(TownFixtures.text(141) + "\nmore")
        }
    }

    @Test
    func `a smaller Tuning moves both edges`() throws {
        var tuning = Tuning.default
        tuning.yourPost.yourPostLength = 3 ... 5
        #expect(try YourPostText("abc", tuning: tuning).value == "abc")
        #expect(try YourPostText("abcde", tuning: tuning).value == "abcde")
        #expect(throws: TownValueError.tooShort(.postText, minimum: 3)) {
            try YourPostText("ab", tuning: tuning)
        }
        #expect(throws: TownValueError.tooLong(.postText, limit: 5)) {
            try YourPostText("abcdef", tuning: tuning)
        }
    }
}
