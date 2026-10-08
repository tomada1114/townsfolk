import SwiftUI
import TownsfolkCore

private enum Layout {
    static let minimumWidth = DesignLock.Window.minimumWidth
    static let minimumHeight = DesignLock.Window.minimumHeight
}

/// Renders the root model's route. The container and its launch-test identifier remain
/// present even while opening or if the store fails; each child owns its existing tasks.
public struct RootView: View {
    /// The default scene size follows the app's design lock.
    public static let defaultSize = CGSize(
        width: DesignLock.Window.defaultWidth,
        height: DesignLock.Window.defaultHeight,
    )
    private let model: AppModel

    public var body: some View {
        VStack(spacing: 0) {
            switch model.route {
            case .opening, .storeUnavailable:
                Color.clear

            case .unavailable:
                ModelUnavailableView(model: model.availability)

            case .firstRun, .founding:
                if let session = model.session {
                    FirstRunView(model: session.firstRun)
                }

            case .town:
                if let session = model.session {
                    TownView(
                        model: session.timeline,
                        composer: session.composer,
                        statusLine: session.statusLine,
                        availability: model.availability,
                    )
                }
            }
        }
        .frame(minWidth: Layout.minimumWidth, minHeight: Layout.minimumHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("townWindow")
        .navigationTitle(model.windowTitle)
        .task { await model.open() }
        .onChange(of: model.availability.availability) { Task { await model.stateChanged() } }
        .onChange(of: model.session?.firstRun.founding?.phase) {
            Task { await model.stateChanged() }
        }
        .onChange(of: model.session?.firstRun.founding == nil) {
            Task { await model.stateChanged() }
        }
        .onChange(of: model.settings.speed) { Task { await model.speedChanged() } }
        .onChange(of: model.settings.displayName) { model.displayNameChanged() }
        .onDisappear { Task { await model.windowClosed() } }
    }

    /// The app constructs this one model and passes it explicitly to each scene.
    public init(model: AppModel) {
        self.model = model
    }
}
