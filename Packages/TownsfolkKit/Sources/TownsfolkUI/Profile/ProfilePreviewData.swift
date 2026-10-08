import SwiftUI
import TownsfolkCore

/// Profiles in each state worth seeing, built from values so a preview never reads a
/// store.
@MainActor
private enum ProfilePreviewData {
    static let mika = Resident.ID()
    static let jun = Resident.ID()
    static let sora = Resident.ID()
    private static let aDay: TimeInterval = 86_400
    private static let aWeek: TimeInterval = 604_800
    private static let longWorryLength = 120
    private static let longWorryRepeats = 3
    static let movedIn = Date(timeIntervalSinceNow: -aWeek)
    static let movedOut = Date(timeIntervalSinceNow: -aDay)

    static let terms = ["Rust", "Film cameras", "Sourdough", "Go", "Bird calls"]

    static var interests: [Interest] {
        terms.compactMap { term in
            try? Interest(
                id: Interest.ID(),
                term: term,
                firstMentionedAt: movedIn,
                lastMentionedAt: movedIn,
                mentions: 1,
            )
        }
    }

    /// A worry of 120 characters, which wraps within the popover's width.
    static var longWorry: String {
        let sentence = "The oven is dying and the bank will not lend. "
        return String(String(repeating: sentence, count: longWorryRepeats).prefix(longWorryLength))
    }

    static func profile(
        name: String = "Mika Tanaka",
        worry: String = "The oven is dying",
        knowsOthers: Bool = true,
        interestCount: Int = 1,
        pastResident: Bool = false,
    ) -> ProfileViewModel? {
        let others = (try? [
            Resident(id: jun, name: "Jun", profile: details(worry: worry), movedInAt: movedIn),
            Resident(id: sora, name: "Sora", profile: details(worry: worry), movedInAt: movedIn),
        ]) ?? []
        let taken = Array(interests.prefix(interestCount))
        let relationships = knowsOthers ? (try? [
            Resident.Relationship(resident: jun, description: "old friend"),
            Resident.Relationship(resident: sora, description: "landlady"),
        ]) ?? [] : []
        guard let resident = try? Resident(
            id: mika,
            name: name,
            profile: details(worry: worry),
            movedInAt: movedIn,
            status: pastResident ? .movedOut : .living,
            movedOutAt: pastResident ? movedOut : nil,
            relationships: relationships,
            interests: taken.map(\.id),
        ) else {
            return nil
        }
        return ProfileViewModel(profile: ResidentProfile(
            resident: resident,
            residents: others + [resident],
            interests: taken,
            locale: .current,
            calendar: .current,
        ))
    }

    static func details(worry: String) throws -> Resident.Profile {
        try Resident.Profile(
            ageGroup: "30s",
            occupation: "Baker",
            hobby: "Film photography",
            worry: worry,
            personality: "Cheerful, a little stubborn",
        )
    }

    @ViewBuilder
    static func popover(_ model: ProfileViewModel?) -> some View {
        if let profile = model?.profile {
            ProfilePopover(profile: profile)
        }
    }
}

#Preview("Living resident") {
    ProfilePreviewData.popover(ProfilePreviewData.profile())
}

#Preview("Living resident, dark") {
    ProfilePreviewData.popover(ProfilePreviewData.profile())
        .preferredColorScheme(.dark)
}

#Preview("No relationships or interests") {
    ProfilePreviewData.popover(ProfilePreviewData.profile(knowsOthers: false, interestCount: 0))
}

#Preview("5 interests") {
    ProfilePreviewData.popover(ProfilePreviewData.profile(interestCount: 5))
}

#Preview("Long worry") {
    ProfilePreviewData.popover(ProfilePreviewData.profile(worry: ProfilePreviewData.longWorry))
}

#Preview("Past resident") {
    ProfilePreviewData.popover(ProfilePreviewData.profile(name: "Hana", pastResident: true))
}

#Preview("Past resident, dark") {
    ProfilePreviewData.popover(ProfilePreviewData.profile(name: "Hana", pastResident: true))
        .preferredColorScheme(.dark)
}
