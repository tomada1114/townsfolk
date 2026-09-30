import Foundation
import Observation

/// Observable presentation state for a ``Counter``.
///
/// Lives in Core (imports Foundation and Observation, never SwiftUI) so its logic stays
/// unit-testable with plain `swift test` and counts toward the coverage floor.
@MainActor
@Observable
public final class CounterViewModel {
    /// The reset button's title, from Core's String Catalog. Wording lives in Core, not
    /// in the view, so a view in `TownsfolkUI` never carries a literal a reader sees.
    public static var resetTitle: LocalizedStringResource {
        LocalizedStringResource(
            "counter.reset",
            defaultValue: "Reset",
            bundle: .module,
            comment: "Button that sets the counter back to zero.",
        )
    }

    /// What VoiceOver reads for the decrement button, whose visible "−" is a glyph, not
    /// a name.
    public static var decrementLabel: LocalizedStringResource {
        LocalizedStringResource(
            "counter.decrement",
            defaultValue: "Decrement",
            bundle: .module,
            comment: "Accessibility label for the button shown as a minus sign, which lowers the counter by one.",
        )
    }

    /// What VoiceOver reads for the increment button, whose visible "+" is a glyph, not
    /// a name.
    public static var incrementLabel: LocalizedStringResource {
        LocalizedStringResource(
            "counter.increment",
            defaultValue: "Increment",
            bundle: .module,
            comment: "Accessibility label for the button shown as a plus sign, which raises the counter by one.",
        )
    }

    /// The underlying domain model.
    public private(set) var counter: Counter

    /// The current counter value.
    public var value: Int {
        counter.value
    }

    /// Whether increment would change the value (false at the upper bound).
    public var canIncrement: Bool {
        !counter.isAtMax
    }

    /// Whether decrement would change the value (false at the lower bound).
    public var canDecrement: Bool {
        !counter.isAtMin
    }

    /// Creates a view model over the default counter (0 in -100...100).
    public init() {
        do {
            counter = try Counter()
        } catch {
            // Unreachable: 0 always lies within the default range.
            preconditionFailure("Counter's default configuration is always valid: \(error)")
        }
    }

    /// Creates a view model over an existing counter.
    public init(counter: Counter) {
        self.counter = counter
    }

    /// Increments the counter, clamping at its upper bound.
    public func increment() {
        counter.increment()
    }

    /// Decrements the counter, clamping at its lower bound.
    public func decrement() {
        counter.decrement()
    }

    /// Resets to 0 when the counter's range contains it, otherwise to its lower bound.
    public func reset() {
        counter.reset()
    }
}
