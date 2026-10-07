import SwiftUI
import TownsfolkCore

/// The key ``SwiftUI/FocusedValues/timeline`` is stored under.
struct TimelineFocusedValueKey: FocusedValueKey {
    typealias Value = TimelineViewModel
}

extension FocusedValues {
    private typealias TimelineKey = TimelineFocusedValueKey

    /// The timeline of the focused town window, which the Town menu's commands act on;
    /// `nil` while no timeline is focused, which disables them. `App/` publishes it with
    /// `.focusedSceneValue(\.timeline, model)`.
    public var timeline: TimelineViewModel? {
        get { self[TimelineKey.self] }
        set { self[TimelineKey.self] = newValue }
    }
}
