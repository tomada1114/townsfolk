/// The instructions and prompts of founding's own calls — the town and each resident
/// (REQ-002, REQ-003). The first scene's prompt is the scene writer's.
enum FoundingPrompts {
    /// The rules every town call follows, with the limits under `tuning`.
    static func townInstructions(tuning: Tuning) -> String {
        let places = tuning.founding.placeCount
        return """
        You invent a small fictional town for a gentle story about everyday life: its name, \
        what it is like, and the places its residents talk about.
        The town is ordinary and peaceful, and nothing in it comes from the real world: no \
        real places, brands, or famous people.
        The name is at most \(tuning.founding.townNameMaxLength) characters.
        The setting is 2 or 3 sentences and at most \(Town.settingMaxLength) characters.
        There are \(places.lowerBound) to \(places.upperBound) places, each named in at most \
        \(Town.placeNameMaxLength) characters.
        The town suits the people who live and work there.
        """
    }

    /// The town call's prompt: the occupations drawn for the first residents, so the town
    /// fits them.
    static func townPrompt(seeds: [ResidentSeed]) -> String {
        let lines = seeds.map { "- \($0.occupation.text)" }
        return (["Invent the town. Its first residents work as:"] + lines).joined(separator: "\n")
    }

    /// The rules every resident call follows.
    static func residentInstructions() -> String {
        """
        You invent one resident of a small fictional town: a first name, a current worry, and \
        how they know the residents already living there.
        The resident is an ordinary person with an everyday life in the town; nothing about \
        them comes from the real world, such as famous people or brands.
        The name is one first name of at most \(Resident.nameMaxLength) characters, unlike \
        every name already taken.
        The worry is a short phrase about something everyday, not a sentence.
        Relationships name only residents listed under Residents so far, at most \
        \(Resident.maxRelationships) of them, each with one line on what they are to each \
        other.
        """
    }

    /// A resident call's prompt: the town, the resident's drawn axes, the names taken,
    /// and the residents invented so far.
    static func residentPrompt(town: Town, seed: ResidentSeed, earlier: [Resident]) -> String {
        let townSection = """
        Town: \(town.name)
        Setting: \(oneLine(town.setting))
        Places: \(town.places.joined(separator: ", "))
        """
        let residentSection = """
        The new resident:
        Life stage: \(seed.lifeStage.text)
        Occupation: \(seed.occupation.text)
        Personality: \(seed.personality.text)
        Hobby: \(seed.hobby.text)
        """
        let names = earlier.isEmpty ? "none" : earlier.map(\.name).joined(separator: ", ")
        var known = ["Names already taken: \(names)"]
        if earlier.isEmpty {
            known.append("Residents so far: none")
        } else {
            known.append("Residents so far:")
            known += earlier.map(summary)
        }
        return [townSection, residentSection, known.joined(separator: "\n")]
            .joined(separator: "\n\n")
    }

    /// One line on a resident invented earlier, as "- Mika: young adult, baker. …".
    private static func summary(_ resident: Resident) -> String {
        let profile = resident.profile
        var line = "- \(resident.name): \(profile.ageGroup), \(profile.occupation)."
        line += " Personality: \(profile.personality). Hobby: \(profile.hobby)."
        line += " Worry: \(oneLine(profile.worry))."
        return line
    }

    /// The text with every line break turned into a space, so it stays one prompt line.
    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
