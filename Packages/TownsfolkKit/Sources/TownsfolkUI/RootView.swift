import SwiftUI

/// Layout metrics for ``RootView``, drawn from the design lock.
private enum Layout {
    static let minimumWidth = DesignLock.Window.minimumWidth
    static let minimumHeight = DesignLock.Window.minimumHeight
}

/// The town window's root: what the one `Window` scene in `App/` holds.
///
/// An empty placeholder for now: the timeline, first run, founding, and the unavailable
/// state become its states later, and each of them keeps the `townWindow` identifier the
/// launch test reads.
public struct RootView: View {
    /// The size the town window opens at, for the scene's `.defaultSize` — `App/` never
    /// spells a size, and ``DesignLock`` stays internal to this module.
    public static let defaultSize = CGSize(
        width: DesignLock.Window.defaultWidth,
        height: DesignLock.Window.defaultHeight,
    )

    public var body: some View {
        Color.clear
            .frame(minWidth: Layout.minimumWidth, minHeight: Layout.minimumHeight)
            .accessibilityIdentifier("townWindow")
    }

    public init() {
        // Public so `App/` can build it; the view model arrives with the town's states.
    }
}

#Preview("Empty") {
    RootView()
}

#Preview("Empty, dark") {
    RootView()
        .preferredColorScheme(.dark)
}
