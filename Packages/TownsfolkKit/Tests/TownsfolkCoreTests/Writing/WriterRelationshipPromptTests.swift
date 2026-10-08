import Foundation
import Testing
import TownsfolkCore

/// The model receives the stored link and its named partner as one scene seed.
@Suite("SceneWriter relationship prompts")
struct WriterRelationshipPromptTests {
    @Test
    func `a relationship seed names its other resident and description in the full prompt`(
    ) async throws {
        try await withStore { store, _ in
            let jun = try EngineCast.jun()
            let mika = try Resident(
                id: Resident.ID(),
                name: "Mika",
                profile: StoreFixtures.profile(),
                movedInAt: StoreFixtures.morning,
                relationships: [.init(resident: jun.id, description: "They play chess together.")],
            )
            let fake = WritingFixtures.fake(WritingFixtures.refusals(3))
            let writer = SceneWriter(model: fake, store: store)
            let request = try SceneRequest(
                you: DisplayName("Tomo"),
                town: WritingFixtures.town(),
                residents: [mika, jun],
                speakers: [mika.id, jun.id],
                seeds: [.profile(mika.id, .relationship(jun.id))],
            )
            _ = try await writer.write(request, at: WritingFixtures.now)
            let expected = [
                "Town: Maplewood",
                "Setting: A small town by a slow river.",
                "Places: the bakery, the river, the station", "",
                "Residents: Mika, Jun", "You: Tomo", "", "Speakers:",
                "- Mika: thirties, baker. Hobby: fishing. Worry: the rent. Personality: cheerful.",
                "- Jun: twenties, librarian. Hobby: chess. Worry: a leaky roof. Personality: shy.",
                "", "Seed: Mika's relationship with Jun: They play chess together.",
            ].joined(separator: "\n")
            #expect(fake.calls.map(\.prompt) == [expected])
            #expect(fake.calls.first?.instructions == WriterPromptTests.instructions)
        }
    }
}
