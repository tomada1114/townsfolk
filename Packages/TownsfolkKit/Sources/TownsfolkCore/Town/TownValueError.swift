/// Why a town value was rejected. Each case names the field and the limit it broke, so a
/// caller can react per case — the composer explains a too-long post, the writer drops
/// a scene the model got wrong — and none carries the offending text: errors reach logs
/// and test output, and nothing a person or the model wrote may (`designing-errors`).
public enum TownValueError: Error, Equatable, Sendable {
    /// The text is empty once trimmed.
    case empty(Field)
    /// The text must be one line and holds a line break.
    case multipleLines(Field)
    /// The field must be absent in this case and is set.
    case notAllowed(Field)
    /// The date comes before the one it must follow.
    case outOfOrder(Field)
    /// The field must be set in this case and is missing.
    case required(Field)
    /// The field points back at the value that holds it.
    case selfReference(Field)
    /// The list has fewer entries than `minimum`.
    case tooFew(Field, minimum: Int)
    /// The trimmed text has more characters than `limit`.
    case tooLong(Field, limit: Int)
    /// The list has more entries than `limit`.
    case tooMany(Field, limit: Int)
    /// The trimmed text has fewer characters than `minimum` — reachable only with a
    /// `Tuning` whose lower bound is above 1.
    case tooShort(Field, minimum: Int)

    /// The field of a town value an error is about.
    public enum Field: Sendable, Equatable {
        /// ``Resident/Profile/ageGroup``.
        case ageGroup
        /// ``DisplayName``.
        case displayName
        /// ``TownEvent/endsAt``.
        case endsAt
        /// ``TownEvent/description``.
        case eventDescription
        /// ``TownEvent/kind``.
        case eventKind
        /// ``Resident/Profile/hobby``.
        case hobby
        /// ``Resident/interests``.
        case interests
        /// ``Interest/lastMentionedAt``.
        case lastMentionedAt
        /// ``Interest/mentions``.
        case mentions
        /// ``Resident/movedOutAt``.
        case movedOutAt
        /// ``Resident/Profile/occupation``.
        case occupation
        /// ``Post/origin``.
        case origin
        /// ``Resident/Profile/personality``.
        case personality
        /// One name in ``Town/places``.
        case place
        /// ``Town/places``, as a list.
        case places
        /// ``Post/text`` or ``YourPostText``.
        case postText
        /// ``TownEvent/relatedResident``.
        case relatedResident
        /// One ``Resident/Relationship/description``.
        case relationshipDescription
        /// ``Resident/relationships``, as a list.
        case relationships
        /// ``Resident/name``.
        case residentName
        /// ``Post/sceneID``.
        case sceneID
        /// ``Town/setting``.
        case setting
        /// ``Interest/term``.
        case term
        /// One tag in ``Post/topicTags``.
        case topicTag
        /// ``Post/topicTags``, as a list.
        case topicTags
        /// ``Town/name``.
        case townName
        /// ``Resident/Profile/worry``.
        case worry
    }
}
