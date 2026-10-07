import SwiftUI
import TownsfolkCore

/// The key ``SwiftUI/FocusedValues/composer`` is stored under.
struct ComposerFocusedValueKey: FocusedValueKey {
    typealias Value = ComposerViewModel
}

extension FocusedValues {
    private typealias ComposerKey = ComposerFocusedValueKey

    /// The composer of the focused town window, which Town › New Post (⌘N) focuses and
    /// Town › Reply (⌘R) puts in reply mode; `nil` while no town window is focused, which
    /// disables both. `App/` publishes it with `.focusedSceneValue(\.composer, composer)`.
    public var composer: ComposerViewModel? {
        get { self[ComposerKey.self] }
        set { self[ComposerKey.self] = newValue }
    }
}
