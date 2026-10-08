import Foundation
import Testing
import TownsfolkCore

/// The prompt sentence ending around a speaker's stored worry.
@Suite("SceneWriter worry prompts")
struct WriterWorryPromptTests {
    private static func request(worry: String, in cast: WritingCast) throws -> SceneRequest {
        let jun = try Resident(
            id: cast.jun.id,
            name: cast.jun.name,
            profile: Resident.Profile(
                ageGroup: "twenties",
                occupation: "librarian",
                hobby: "chess",
                worry: worry,
                personality: "shy",
            ),
            movedInAt: cast.jun.movedInAt,
        )
        let residents = cast.residents.map { $0.id == jun.id ? jun : $0 }
        return try SceneRequest(
            you: DisplayName("Tomo"),
            town: WritingFixtures.town(),
            residents: residents,
            speakers: [jun.id],
            seeds: [.topic("new bread")],
        )
    }

    private static func snapshot(worryLine: String) -> String {
        let lines = [
            "Town: Maplewood",
            "Setting: A small town by a slow river.",
            "Places: the bakery, the river, the station",
            "",
            "Residents: Mika, Jun, Aki",
            "Past residents: Sora",
            "You: Tomo",
            "",
            "Speakers:",
            "- Jun: twenties, librarian. Hobby: chess. \(worryLine)",
            "",
            #"Seed: the topic "new bread", still going."#,
        ]
        return lines.joined(separator: "\n")
    }

    @Test(arguments: [
        ("unpunctuated", "the rent", "Worry: the rent. Personality: shy."),
        ("period", "Rain.", "Worry: Rain. Personality: shy."),
        ("exclamation mark", "Rain!", "Worry: Rain! Personality: shy."),
        ("question mark", "Rain?", "Worry: Rain? Personality: shy."),
    ])
    func `a speaker worry keeps its ending in the prompt snapshot`(
        label: String,
        worry: String,
        expectedWorryLine: String,
    ) async throws {
        try await withWritingStore { store, cast in
            let request = try Self.request(worry: worry, in: cast)
            let answer = WritingFixtures.content([DraftPost(speaker: "Jun", text: "Rain again.")])
            let fake = WritingFixtures.fake([.content(answer)])
            let writer = SceneWriter(model: fake, store: store)

            _ = try await writer.write(request, at: WritingFixtures.now)

            let call = try #require(fake.calls.first)
            #expect(call.prompt == Self.snapshot(worryLine: expectedWorryLine), "case: \(label)")
        }
    }
}
