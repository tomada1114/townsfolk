/// The instructions and prompts of the engine's calls besides scenes (requirements §3.6):
/// an event's description, and a newcomer moving in. Every value goes through
/// ``ScenePromptBuilder/oneLine(_:)``, so none spans lines.
enum TownChangePrompts {
    /// The rules every event description call follows.
    static func eventInstructions() -> String {
        """
        You write one line for the shared board of a small fictional town, announcing \
        something that has just started happening there.
        The town is ordinary and peaceful, and nothing in it comes from the real world: no \
        real places, brands, or famous people.
        The line names no person; it may name one of the town's places.
        The line is one sentence of at most \(TownEvent.descriptionMaxLength) characters, \
        such as "It started raining."
        """
    }

    /// An event description call's prompt: the town, and the kind the rules picked.
    static func eventPrompt(town: Town, kind: SeedTables.EventKind) -> String {
        [townSection(town), "What starts now: \(ScenePromptBuilder.oneLine(kind.text))"]
            .joined(separator: "\n\n")
    }

    /// The rules every newcomer call follows.
    static func newcomerInstructions() -> String {
        """
        You invent one newcomer moving into a small fictional town: a first name, a current \
        worry, and how they know the residents already living there.
        The newcomer is an ordinary person with an everyday life in the town; nothing about \
        them comes from the real world, such as famous people or brands.
        The name is one first name of at most \(Resident.nameMaxLength) characters, unlike \
        every name already taken.
        The newcomer is unlike everyone listed under Residents so far and Past residents.
        The worry is a short phrase about something everyday, not a sentence.
        Relationships name only residents listed under Residents so far, at most \
        \(Resident.maxRelationships) of them, each with one line on what they are to each \
        other; a newcomer may know none of them yet.
        """
    }

    /// A newcomer call's prompt: the town, the drawn axes, every name taken, and every
    /// current resident's occupation and personality. Past profiles may be left out to
    /// fit the context, but their names remain taken (requirements.md:259–:260).
    static func newcomerPrompt(
        town: Town,
        seed: NewcomerInput,
        residents: [Resident],
        withoutPastProfiles: Set<Resident.ID>,
    ) -> String {
        let newcomer = """
        The new resident, moving in now:
        Life stage: \(ScenePromptBuilder.oneLine(seed.axes.lifeStage.text))
        Occupation: \(ScenePromptBuilder.oneLine(seed.axes.occupation.text))
        Personality: \(ScenePromptBuilder.oneLine(seed.axes.personality.text))
        Hobby: \(ScenePromptBuilder.oneLine(seed.axes.hobby.text))
        """
        let interest = seed.name.map { name in
            """
            Name brought up by the user: "\(ScenePromptBuilder.oneLine(name.term))". \
            The newcomer starts with an interest in it.
            """
        }
        let names = residents.map { ScenePromptBuilder.oneLine($0.name) }
        let living = residents.filter { $0.status == .living }
        let past = residents.filter { $0.status == .movedOut }
        var known =
            ["Names already taken: \(names.isEmpty ? "none" : names.joined(separator: ", "))"]
        known += list("Residents so far", living)
        known += list("Past residents", past, withoutProfiles: withoutPastProfiles)
        return [townSection(town), newcomer, interest, known.joined(separator: "\n")]
            .compactMap(\.self).joined(separator: "\n\n")
    }

    private static func townSection(_ town: Town) -> String {
        """
        Town: \(ScenePromptBuilder.oneLine(town.name))
        Setting: \(ScenePromptBuilder.oneLine(town.setting))
        Places: \(town.places.map(ScenePromptBuilder.oneLine).joined(separator: ", "))
        """
    }

    /// `heading`, then one line per resident, as "- Mika: baker, cheerful."; "none" for
    /// nobody.
    private static func list(
        _ heading: String,
        _ residents: [Resident],
        withoutProfiles: Set<Resident.ID> = [],
    ) -> [String] {
        guard !residents.isEmpty else {
            return ["\(heading): none"]
        }
        return ["\(heading):"] + residents.map { resident in
            let name = ScenePromptBuilder.oneLine(resident.name)
            guard !withoutProfiles.contains(resident.id) else {
                return "- \(name)"
            }
            let occupation = ScenePromptBuilder.oneLine(resident.profile.occupation)
            let personality = ScenePromptBuilder.oneLine(resident.profile.personality)
            return "- \(name): \(occupation), \(personality)."
        }
    }
}
