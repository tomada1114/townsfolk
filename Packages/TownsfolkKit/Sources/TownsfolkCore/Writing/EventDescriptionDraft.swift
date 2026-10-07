import FoundationModels

/// What an event call asks the model to write: the event's one line (requirements §3.6,
/// :256, :396). Rules pick the kind, its duration, and when it starts; the model only
/// says what is happening (`docs/architecture.md` › Principles).
///
/// The guide is part of what the model is told; it states the limit, which the engine
/// checks again through ``TownEvent``'s own initializer. Its number is a literal because
/// a guide is fixed at compile time: it mirrors ``TownEvent/descriptionMaxLength`` (120).
@Generable
public struct EventDescriptionDraft: Equatable, Sendable {
    /// What is happening in town now.
    @Guide(
        description: """
        One sentence of at most 120 characters on what has just started happening in town, \
        naming no person.
        """,
    )
    public var description: String

    /// Creates an event draft, as a test scripts the model's answer.
    public init(description: String) {
        self.description = description
    }
}
