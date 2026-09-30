import Foundation
import Testing
import TownsfolkCore

@Suite("Resident")
struct ResidentTests {
    let id = Resident.ID()

    private func profile() throws(TownValueError) -> Resident.Profile {
        try Resident.Profile(
            ageGroup: "thirties",
            occupation: "baker",
            hobby: "birdwatching",
            worry: "the oven is getting old",
            personality: "cheerful, a little nosy",
        )
    }

    private func resident(
        name: String = "Mika Tanaka",
        status: Resident.Status = .living,
        movedOutAt: Date? = nil,
        relationships: [Resident.Relationship] = [],
        interests: [Interest.ID] = [],
    ) throws(TownValueError) -> Resident {
        try Resident(
            id: id,
            name: name,
            profile: profile(),
            movedInAt: TownFixtures.movedIn,
            status: status,
            movedOutAt: movedOutAt,
            relationships: relationships,
            interests: interests,
        )
    }

    private func relationships(_ count: Int) throws(TownValueError) -> [Resident.Relationship] {
        var result: [Resident.Relationship] = []
        for _ in 0 ..< count {
            try result.append(Resident.Relationship(
                resident: Resident.ID(),
                description: "neighbor",
            ))
        }
        return result
    }

    // MARK: - Fields

    @Test
    func `a resident keeps every field it was given`() throws {
        let sora = Resident.ID()
        let rust = Interest.ID()
        let friend = try Resident.Relationship(resident: sora, description: " old school friend ")
        let mika = try resident(
            name: "  Mika Tanaka ",
            relationships: [friend],
            interests: [rust],
        )
        #expect(mika.id == id)
        #expect(mika.name == "Mika Tanaka")
        #expect(try mika.profile == profile())
        #expect(mika.relationships == [friend])
        #expect(friend.resident == sora)
        #expect(friend.description == "old school friend")
        #expect(mika.interests == [rust])
        #expect(mika.status == .living)
        #expect(mika.movedInAt == TownFixtures.movedIn)
        #expect(mika.movedOutAt == nil)
    }

    @Test
    func `a profile keeps its fields trimmed`() throws {
        let trimmed = try Resident.Profile(
            ageGroup: " teens ",
            occupation: "student\n",
            hobby: "\tchess",
            worry: " exams ",
            personality: " shy ",
        )
        #expect(trimmed.ageGroup == "teens")
        #expect(trimmed.occupation == "student")
        #expect(trimmed.hobby == "chess")
        #expect(trimmed.worry == "exams")
        #expect(trimmed.personality == "shy")
    }

    // MARK: - Name

    @Test
    func `a name of 20 characters is accepted and 21 is too long`() throws {
        #expect(try resident(name: TownFixtures.text(20)).name.count == 20)
        #expect(throws: TownValueError.tooLong(.residentName, limit: 20)) {
            try resident(name: TownFixtures.text(21))
        }
    }

    @Test
    func `a blank name is empty`() {
        #expect(throws: TownValueError.empty(.residentName)) {
            try resident(name: " ")
        }
    }

    // MARK: - Profile fields

    @Test(arguments: [
        (TownValueError.Field.ageGroup, 0),
        (.occupation, 1),
        (.hobby, 2),
        (.worry, 3),
        (.personality, 4),
    ])
    func `every profile field must be non-empty`(field: TownValueError.Field, blankIndex: Int) {
        var values = ["thirties", "baker", "birdwatching", "the oven", "cheerful"]
        values[blankIndex] = "  "
        #expect(throws: TownValueError.empty(field)) {
            try Resident.Profile(
                ageGroup: values[0],
                occupation: values[1],
                hobby: values[2],
                worry: values[3],
                personality: values[4],
            )
        }
    }

    // MARK: - Relationships

    @Test(arguments: [0, 3])
    func `zero to three relationships are accepted`(count: Int) throws {
        #expect(try resident(relationships: relationships(count)).relationships.count == count)
    }

    @Test
    func `four relationships are too many`() {
        #expect(throws: TownValueError.tooMany(.relationships, limit: 3)) {
            try resident(relationships: relationships(4))
        }
    }

    @Test
    func `a relationship pointing at the resident itself is rejected`() throws {
        let toSelf = try Resident.Relationship(resident: id, description: "myself")
        #expect(throws: TownValueError.selfReference(.relationships)) {
            try resident(relationships: [toSelf])
        }
    }

    @Test
    func `a relationship's description is one non-empty line`() {
        #expect(throws: TownValueError.empty(.relationshipDescription)) {
            try Resident.Relationship(resident: Resident.ID(), description: " ")
        }
        #expect(throws: TownValueError.multipleLines(.relationshipDescription)) {
            try Resident.Relationship(resident: Resident.ID(), description: "sister\nand rival")
        }
    }

    // MARK: - Interests

    @Test(arguments: [0, 5])
    func `zero to five interests are accepted`(count: Int) throws {
        let interests = (0 ..< count).map { _ in Interest.ID() }
        #expect(try resident(interests: interests).interests == interests)
    }

    @Test
    func `six interests are too many`() {
        let interests = (0 ..< 6).map { _ in Interest.ID() }
        #expect(throws: TownValueError.tooMany(.interests, limit: 5)) {
            try resident(interests: interests)
        }
    }

    // MARK: - Status and moved-out date

    @Test
    func `a resident who moved out keeps the date`() throws {
        let gone = try resident(status: .movedOut, movedOutAt: TownFixtures.anHourLater)
        #expect(gone.status == .movedOut)
        #expect(gone.movedOutAt == TownFixtures.anHourLater)
    }

    @Test
    func `moving out on the day of moving in is accepted`() throws {
        let gone = try resident(status: .movedOut, movedOutAt: TownFixtures.movedIn)
        #expect(gone.movedOutAt == TownFixtures.movedIn)
    }

    @Test
    func `moved out without a date is rejected`() {
        #expect(throws: TownValueError.required(.movedOutAt)) {
            try resident(status: .movedOut, movedOutAt: nil)
        }
    }

    @Test
    func `moved out before moving in is rejected`() {
        #expect(throws: TownValueError.outOfOrder(.movedOutAt)) {
            try resident(status: .movedOut, movedOutAt: TownFixtures.anHourEarlier)
        }
    }

    @Test
    func `a living resident with a moved-out date is rejected`() {
        #expect(throws: TownValueError.notAllowed(.movedOutAt)) {
            try resident(status: .living, movedOutAt: TownFixtures.anHourLater)
        }
    }
}
