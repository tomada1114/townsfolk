/// One of founding's three visible steps (`docs/product/ux-flows.md` › S3), reported as
/// each finishes: the town, then the residents, then the first scene. Nothing else about
/// the calls is reported: retries and failed attempts stay out of sight.
public enum FoundingProgress: Sendable, Equatable {
    /// The first scene is written — the third step.
    case firstScene
    /// Every first resident is invented — the second step.
    case residents
    /// The town is invented — the first step.
    case town
}

/// How a founding run ended. No case carries anything the model or you wrote: an
/// outcome is logged and may reach test output (`designing-errors`).
public enum FoundingOutcome: Sendable, Equatable {
    /// The failed attempts reached `Tuning.founding.foundingAttempts`, or the final write
    /// failed; nothing is stored, and founding may be tried again from the start.
    case failed
    /// The town, its residents, the founding row, and the first scene are stored.
    case founded
    /// The model is unavailable for this reason; nothing is stored, and founding waits
    /// until the model is back (requirements.md:146).
    case unavailable(ModelAvailability)
}
