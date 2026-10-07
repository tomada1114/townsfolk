/// Whether the on-device model can be called now, and if not, why.
///
/// An answer rather than an error: Apple Intelligence being off is a state the town shows
/// and waits out (ux-flows S7), not a call that failed (`designing-errors`). Each
/// unavailable case is one the person or the Mac can be in, named for what the town says
/// about it rather than for the framework's spelling.
public enum ModelAvailability: Equatable, Hashable, Sendable {
    /// Apple Intelligence is turned off in System Settings; turning it on is the person's
    /// choice.
    case appleIntelligenceOff
    /// The model can be called.
    case available
    /// This Mac cannot run Apple Intelligence at all.
    case deviceNotEligible
    /// Apple Intelligence is on, but the model is not ready yet — still downloading, most
    /// often — so it is worth asking again later.
    case modelNotReady
}
