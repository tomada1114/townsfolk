import Foundation
import Testing
import TownsfolkCore

@Suite("Interest")
struct InterestTests {
    private func interest(
        term: String = "Rust",
        lastMentionedAt: Date = TownFixtures.anHourLater,
        mentions: Int = 2,
    ) throws(TownValueError) -> Interest {
        try Interest(
            id: Interest.ID(),
            term: term,
            firstMentionedAt: TownFixtures.movedIn,
            lastMentionedAt: lastMentionedAt,
            mentions: mentions,
        )
    }

    @Test
    func `an interest keeps every field it was given`() throws {
        let id = Interest.ID()
        let source = [Post.ID(), Post.ID()]
        let rust = try Interest(
            id: id,
            term: " Rust ",
            firstMentionedAt: TownFixtures.movedIn,
            lastMentionedAt: TownFixtures.anHourLater,
            mentions: 2,
            sourcePosts: source,
        )
        #expect(rust.id == id)
        #expect(rust.term == "Rust")
        #expect(rust.firstMentionedAt == TownFixtures.movedIn)
        #expect(rust.lastMentionedAt == TownFixtures.anHourLater)
        #expect(rust.mentions == 2)
        #expect(rust.sourcePosts == source)
    }

    @Test
    func `an interest starts with no source posts`() throws {
        #expect(try interest().sourcePosts.isEmpty)
    }

    @Test
    func `a term of 40 characters is accepted and 41 is too long`() throws {
        #expect(try interest(term: TownFixtures.text(40)).term.count == 40)
        #expect(throws: TownValueError.tooLong(.term, limit: 40)) {
            try interest(term: TownFixtures.text(41))
        }
    }

    @Test
    func `a blank term is empty`() {
        #expect(throws: TownValueError.empty(.term)) {
            try interest(term: " ")
        }
    }

    @Test
    func `a single mention on one moment is accepted`() throws {
        let once = try interest(lastMentionedAt: TownFixtures.movedIn, mentions: 1)
        #expect(once.mentions == 1)
        #expect(once.lastMentionedAt == once.firstMentionedAt)
    }

    @Test
    func `zero mentions are too few`() {
        #expect(throws: TownValueError.tooFew(.mentions, minimum: 1)) {
            try interest(mentions: 0)
        }
    }

    @Test
    func `a last mention before the first is rejected`() {
        #expect(throws: TownValueError.outOfOrder(.lastMentionedAt)) {
            try interest(lastMentionedAt: TownFixtures.anHourEarlier)
        }
    }
}
