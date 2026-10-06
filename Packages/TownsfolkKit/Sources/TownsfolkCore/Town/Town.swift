import Foundation

/// The town itself — there is always exactly one (requirements §3.9, §5), which is why it
/// carries no id. Everything in it is invented by the model at founding and never edited.
public struct Town: Sendable, Equatable {
    /// The longest setting, in characters (requirements.md:393).
    public static let settingMaxLength = 400
    /// The longest place name, in characters (requirements.md:393).
    public static let placeNameMaxLength = 30

    /// The town's name, shown as the window title.
    public let name: String
    /// A few sentences on what the town is like, given to every scene.
    public let setting: String
    /// The named places residents talk about.
    public let places: [String]
    /// When you moved in — the time of the founding row.
    public let foundedAt: Date

    /// Creates a town, trimming every text at both ends.
    /// - Throws: ``TownValueError`` for a name over `tuning.founding.townNameMaxLength`,
    ///   a place count outside `tuning.founding.placeCount`, or any text empty or over
    ///   its limit.
    public init(
        name: String,
        setting: String,
        places: [String],
        foundedAt: Date,
        tuning: Tuning = .default,
    ) throws(TownValueError) {
        self.name = try TextRule.validated(
            name,
            .townName,
            length: 1 ... tuning.founding.townNameMaxLength,
            singleLine: false,
        )
        self.setting = try TextRule.validated(
            setting,
            .setting,
            length: 1 ... Self.settingMaxLength,
            singleLine: false,
        )
        try TextRule.checkCount(places.count, .places, allowed: tuning.founding.placeCount)
        var validPlaces: [String] = []
        for place in places {
            try validPlaces.append(
                TextRule.validated(
                    place,
                    .place,
                    length: 1 ... Self.placeNameMaxLength,
                    singleLine: false,
                ),
            )
        }
        self.places = validPlaces
        self.foundedAt = foundedAt
    }
}
