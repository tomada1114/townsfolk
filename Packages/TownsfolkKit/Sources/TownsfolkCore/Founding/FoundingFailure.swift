/// Why one founding attempt failed — logged `.public`, so it names a kind of failure and
/// never what the model wrote.
enum FoundingFailure: String, Error, Equatable {
    /// A resident's answer broke one of its limits.
    case invalidResident
    /// The town's answer broke one of its limits.
    case invalidTown
    /// The answer did not decode into the output type.
    case malformedOutput
    /// The call failed for another reason.
    case modelFailed
    /// The call did not fit the context.
    case overflow
    /// The call was refused.
    case refused
    /// A resident's name repeats an earlier one's.
    case repeatedName
    /// The scene writer skipped the first scene.
    case sceneSkipped
}
