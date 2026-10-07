import FoundationModels

/// What the founding town call asks the model to invent: the town's name, its setting,
/// and the places its residents talk about (requirements §3.1, :393).
///
/// The guides are part of what the model is told; they state the limits, which
/// ``Founder`` checks again through ``Town``'s own initializer. The numbers in the
/// descriptions are literals because a guide is fixed at compile time: they mirror
/// `Tuning.founding.townNameMaxLength` (30), ``Town/settingMaxLength`` (400),
/// `Tuning.founding.placeCount` (3–5), and ``Town/placeNameMaxLength`` (30), and change
/// with them.
@Generable
public struct TownDraft: Equatable, Sendable {
    /// The town's name.
    @Guide(description: "The town's name, at most 30 characters.")
    public var name: String
    /// What the town is like.
    @Guide(description: "What the town is like, in 2 or 3 sentences and at most 400 characters.")
    public var setting: String
    /// The named places residents talk about.
    @Guide(
        description: "3 to 5 named places in town that residents talk about, each at most 30 characters.",
        .count(Tuning.default.founding.placeCount),
    )
    public var places: [String]

    /// Creates a town draft, as a test scripts the model's answer.
    public init(name: String, setting: String, places: [String]) {
        self.name = name
        self.setting = setting
        self.places = places
    }
}
