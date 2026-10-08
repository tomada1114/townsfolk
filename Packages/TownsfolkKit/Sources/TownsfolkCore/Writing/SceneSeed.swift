/// What a scene is about (requirements §3.2). The engine's rules choose it and the order
/// seeds are tried in — never the model, and never the writer, which only renders the
/// seed it is handed and moves to the caller's next one after a refusal
/// (`docs/architecture.md` › Principles).
public enum SceneSeed: Sendable, Equatable {
    /// An ongoing event, or a move that just happened — an ended event, told as news.
    case event(TownEvent)
    /// A name you brought up.
    case name(Interest)
    /// Something from the profile of the resident with this id, one of the roster.
    case profile(Resident.ID, ProfileAspect)
    /// A topic still going — a recent scene's topic tag.
    case topic(String)
    /// One of your posts. When `quoted`, the scene's first post replies to it; a
    /// `leadSpeaker`, one of the speakers, writes the first post.
    case yourPost(Post, quoted: Bool, leadSpeaker: Resident.ID?)

    /// The part of a resident's profile a ``profile(_:_:)`` seed is about.
    public enum ProfileAspect: Sendable, Hashable, CaseIterable {
        /// What they do for fun.
        case hobby
        /// What they do for a living.
        case occupation
        /// How they come across.
        case personality
        /// A stored link to this other resident, including someone who moved away.
        case relationship(Resident.ID)
        /// What they worry about.
        case worry

        /// Scalar aspects used by founding; relationship candidates need a resident's
        /// stored links and the roster, so ordinary scene casting adds those separately.
        public static let allCases: [Self] = [.hobby, .occupation, .personality, .worry]
    }
}
