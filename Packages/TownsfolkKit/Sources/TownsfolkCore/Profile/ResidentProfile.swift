import Foundation

/// One resident as the profile popover shows them (ux-flows S4): the name, the
/// occupation-and-age line, personality, hobby, worry, whom they know, what they took up
/// from you, and when they moved in — or out. Read-only: residents are never curated
/// (requirements §2).
public struct ResidentProfile: Sendable, Equatable {
    /// The name, as the town invented it.
    public let name: String
    /// Whether they have moved out; the name is then drawn in the secondary style.
    public let isPastResident: Bool
    /// "{occupation} · {age group}".
    public let summary: LocalizedStringResource
    /// How they come across.
    public let personality: String
    /// What they do for fun.
    public let hobby: String
    /// What is on their mind.
    public let worry: String
    /// One "{name} — {description}" line per relationship (0–3); the row is omitted when
    /// empty.
    public let knows: [LocalizedStringResource]
    /// One "{term} (from you)" line per interest taken up (0–5); the row is omitted when
    /// empty.
    public let interests: [LocalizedStringResource]
    /// "Moved in {date}", or "Moved out {date}" for a past resident.
    public let moveLine: LocalizedStringResource

    /// Builds `resident`'s profile.
    ///
    /// - Parameters:
    ///   - resident: Whose profile it is.
    ///   - residents: Every resident, for the names of those `resident` knows; a
    ///     relationship to someone not among them is left out.
    ///   - interests: The interests that may be shown; one `resident` took up that is not
    ///     among them — excluded from later contexts (§3.11) — is left out.
    ///   - locale: The locale the move date is written in.
    ///   - calendar: The calendar and time zone the move date is written in.
    package init(
        resident: Resident,
        residents: [Resident],
        interests: [Interest],
        locale: Locale,
        calendar: Calendar,
    ) {
        name = resident.name
        isPastResident = resident.status == .movedOut
        summary = ProfileWording.summary(
            occupation: resident.profile.occupation,
            ageGroup: resident.profile.ageGroup,
        )
        personality = resident.profile.personality
        hobby = resident.profile.hobby
        worry = resident.profile.worry
        let names = Dictionary(residents.map { ($0.id, $0.name) }) { first, _ in first }
        knows = resident.relationships.compactMap { relationship in
            names[relationship.resident].map { name in
                ProfileWording.knowsLine(name: name, description: relationship.description)
            }
        }
        let terms = Dictionary(interests.map { ($0.id, $0.term) }) { first, _ in first }
        self.interests = resident.interests.compactMap { id in
            terms[id].map(ProfileWording.interestLine(term:))
        }
        let style = Date.FormatStyle(
            locale: locale,
            calendar: calendar,
            timeZone: calendar.timeZone,
        )
        .month(.abbreviated)
        .day()
        if let movedOutAt = resident.movedOutAt {
            moveLine = ProfileWording.movedOut(date: movedOutAt.formatted(style))
        } else {
            moveLine = ProfileWording.movedIn(date: resident.movedInAt.formatted(style))
        }
    }
}
