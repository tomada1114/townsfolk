import Foundation
import Testing
import TownsfolkCore

@Suite("TownEvent")
struct TownEventTests {
    private func event(
        kind: EventKindID = EventKindID(rawValue: "rain"),
        description: String = "It started raining.",
        endsAt: Date = TownFixtures.anHourLater,
        status: TownEvent.Status = .ongoing,
        relatedResident: Resident.ID? = nil,
    ) throws(TownValueError) -> TownEvent {
        try TownEvent(
            id: TownEvent.ID(),
            kind: kind,
            description: description,
            startsAt: TownFixtures.movedIn,
            endsAt: endsAt,
            status: status,
            relatedResident: relatedResident,
        )
    }

    // MARK: - Fields

    @Test
    func `an event keeps every field it was given`() throws {
        let id = TownEvent.ID()
        let mika = Resident.ID()
        let move = try TownEvent(
            id: id,
            kind: .moveIn,
            description: " Mika moved in. ",
            startsAt: TownFixtures.movedIn,
            endsAt: TownFixtures.anHourLater,
            status: .ended,
            relatedResident: mika,
        )
        #expect(move.id == id)
        #expect(move.kind == .moveIn)
        #expect(move.description == "Mika moved in.")
        #expect(move.startsAt == TownFixtures.movedIn)
        #expect(move.endsAt == TownFixtures.anHourLater)
        #expect(move.status == .ended)
        #expect(move.relatedResident == mika)
    }

    @Test
    func `a new event is ongoing with no related resident`() throws {
        let rain = try TownEvent(
            id: TownEvent.ID(),
            kind: EventKindID(rawValue: "rain"),
            description: "It started raining.",
            startsAt: TownFixtures.movedIn,
            endsAt: TownFixtures.anHourLater,
        )
        #expect(rain.status == .ongoing)
        #expect(rain.relatedResident == nil)
    }

    // MARK: - The fixed kinds

    @Test
    func `the fixed kinds are spelled as the seed tables carry them`() {
        #expect(EventKindID.moveIn.rawValue == "move-in")
        #expect(EventKindID.moveOut.rawValue == "move-out")
        #expect(EventKindID.founding.rawValue == "founding")
    }

    @Test
    func `a kind from the seed tables is its raw string`() {
        let powerCut = EventKindID(rawValue: "power-cut")
        let samePowerCut = EventKindID(rawValue: "power-cut")
        #expect(powerCut == samePowerCut)
        #expect(powerCut != .founding)
    }

    @Test
    func `an empty kind is rejected`() {
        #expect(throws: TownValueError.empty(.eventKind)) {
            try event(kind: EventKindID(rawValue: ""))
        }
    }

    @Test(arguments: [EventKindID.moveIn, .moveOut])
    func `a move must name its resident`(kind: EventKindID) throws {
        #expect(throws: TownValueError.required(.relatedResident)) {
            try event(kind: kind)
        }
        let mika = Resident.ID()
        #expect(try event(kind: kind, relatedResident: mika).relatedResident == mika)
    }

    @Test
    func `the founding row needs no resident`() throws {
        let founding = try event(kind: .founding, endsAt: TownFixtures.movedIn, status: .ended)
        #expect(founding.relatedResident == nil)
    }

    // MARK: - Description

    @Test
    func `a description of 120 characters is accepted and 121 is too long`() throws {
        #expect(try event(description: TownFixtures.text(120)).description.count == 120)
        #expect(throws: TownValueError.tooLong(.eventDescription, limit: 120)) {
            try event(description: TownFixtures.text(121))
        }
    }

    @Test
    func `a blank description is empty`() {
        #expect(throws: TownValueError.empty(.eventDescription)) {
            try event(description: "  ")
        }
    }

    @Test
    func `a description is one line`() {
        #expect(throws: TownValueError.multipleLines(.eventDescription)) {
            try event(description: "Rain.\nThen more rain.")
        }
    }

    // MARK: - Dates

    @Test
    func `an event that ends as it starts is accepted`() throws {
        #expect(try event(endsAt: TownFixtures.movedIn).endsAt == TownFixtures.movedIn)
    }

    @Test
    func `an event that ends before it starts is rejected`() {
        #expect(throws: TownValueError.outOfOrder(.endsAt)) {
            try event(endsAt: TownFixtures.anHourEarlier)
        }
    }
}
