import Foundation
import Observation

/// Whether the town can be written right now, and what the window says when it cannot
/// (ux-flows S7): one model behind both the full-window message and the town banner.
///
/// It reads ``LanguageModelProviding/availability`` once when created and again on each
/// ``refresh()``, which the view calls whenever the window becomes active, so turning
/// Apple Intelligence on, or the download finishing, shows without a restart.
@MainActor
@Observable
public final class AvailabilityViewModel {
    /// The port's last answer.
    public private(set) var availability: ModelAvailability

    private let provider: any LanguageModelProviding

    /// Whether either view shows anything.
    public var isUnavailable: Bool {
        availability != .available
    }

    /// What the window says and offers, or `nil` while the model is available.
    public var notice: AvailabilityNotice? {
        AvailabilityNotice(availability)
    }

    /// Creates the model over `provider`, asking it once.
    public init(provider: any LanguageModelProviding) {
        self.provider = provider
        let answer = provider.availability
        availability = answer
        AppLog.model.info("availability: \(String(describing: answer), privacy: .public)")
    }

    // MARK: Actions

    /// Asks the port again; the answer replaces the last one, so the later of two calls
    /// wins. Logs only a change, and only as the enum case.
    public func refresh() {
        let answer = provider.availability
        guard answer != availability else {
            return
        }
        availability = answer
        AppLog.model.info("availability changed: \(String(describing: answer), privacy: .public)")
    }
}
