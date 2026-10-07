import Foundation

/// One of S3's three lines (ux-flows S3): a founding step, its words, and whether #20's
/// founder has reported it finished.
public struct FoundingStepLine: Identifiable, Equatable, Sendable {
    /// The step this line stands for.
    public let step: FoundingProgress
    /// The line's words: "Drawing the streets", "Meeting the neighbors", "Saying hello".
    public let title: LocalizedStringResource
    /// Whether the founder reported the step finished; the view shows a check mark then,
    /// and a dotted circle before.
    public let isDone: Bool

    /// The step, which appears once per screen.
    public var id: FoundingProgress {
        step
    }

    /// What VoiceOver says for the line's symbol: "Done" or "Not yet", so the state is
    /// never carried by the symbol alone.
    public var status: LocalizedStringResource {
        FirstRunWording.stepStatus(isDone: isDone)
    }
}
