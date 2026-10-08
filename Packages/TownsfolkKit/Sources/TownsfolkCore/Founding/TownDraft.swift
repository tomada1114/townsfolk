import FoundationModels

/// What the founding town call asks the model to invent: the town's name, its setting,
/// and the places its residents talk about (requirements §3.1, :393).
///
/// The fixed guides defer tunable name length and place count to the runtime instructions,
/// so they agree with the caller's injected `Tuning`. ``Founder`` checks every limit
/// again through ``Town``'s initializer. Immutable setting and place-name lengths
/// remain in the descriptions; schema tests keep their compile-time literals in sync
/// with ``Town/settingMaxLength`` and ``Town/placeNameMaxLength``.
@Generable
public struct TownDraft: Equatable, Sendable {
    /// The town's name.
    @Guide(description: "The town's name, within the character limit in the instructions.")
    public var name: String
    /// What the town is like.
    @Guide(description: "What the town is like, in 2 or 3 sentences and at most 400 characters.")
    public var setting: String
    /// The named places residents talk about.
    @Guide(
        description: """
        The number of places requested in the instructions, named places in town that residents \
        talk about, each at most 30 characters.
        """,
    )
    public var places: [String]

    /// Creates a town draft, as a test scripts the model's answer.
    public init(name: String, setting: String, places: [String]) {
        self.name = name
        self.setting = setting
        self.places = places
    }
}
