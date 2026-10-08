import SwiftUI
import TownsfolkCore

/// One status line: the symbol inline before the text, monochrome, in the text's style.
private struct StatusLineText: View {
    let text: LocalizedStringResource
    let symbol: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignLock.Spacing.extraSmall) {
            if let symbol {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            }
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.callout)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(StatusLineViewModel.accessibilityLabel))
        .accessibilityValue(Text(text))
        .accessibilityIdentifier("townStatusLine")
    }
}

/// Lines in each state worth seeing, built with no store.
@MainActor
private enum StatusLinePreviewData {
    static let weather = EventKindID(rawValue: "weather-turns")
    static let symbols: [EventKindID: String] = [.founding: "house", weather: "cloud.sun.rain"]
    static let eventAndTopic = model(
        .eventAndTopic(event: "Rain since noon", topic: "the bakery's new bread"),
        kind: weather,
    )
    static let topicOnly = model(.topic("the bakery's new bread"), kind: nil)
    static let quiet = model(.quiet(town: "Maplewood"), kind: nil)
    /// A 300-character line, to see the tail cut at the narrowest width.
    static let long = model(
        .eventAndTopic(
            event: String(
                repeating: "Rain over the river and the station all afternoon. ",
                count: repeats,
            ),
            topic: String(
                repeating: "the bakery's new bread and the goose-noise oven ",
                count: repeats,
            ),
        ),
        kind: weather,
    )
    /// How many times each phrase repeats in ``long``, which makes it 300 characters.
    private static let repeats = 3

    static func model(_ line: StatusLineContent.Line, kind: EventKindID?) -> StatusLineViewModel {
        StatusLineViewModel(
            content: StatusLineContent(line: line, eventKind: kind),
            eventSymbols: symbols,
            environment: TimelineEnvironment(),
        )
    }
}

/// The town's status line (ux-flows S1): the leading event's symbol, then one line cut at
/// the tail, crossfading over 200 ms when what it says changes. It renders
/// ``StatusLineViewModel`` and decides nothing; `.task` runs the model while it is on
/// screen. Before there is a town it shows nothing.
///
/// The crossfade is opacity only, so it stays under Reduce Motion
/// (`docs/design/ux-guidelines.md` › Motion).
struct StatusLineView: View {
    let model: StatusLineViewModel

    var body: some View {
        ZStack(alignment: .leading) {
            if let text = model.text {
                StatusLineText(text: text, symbol: model.symbol)
                    .id(model.content)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            .easeInOut(duration: DesignLock.Motion.statusLineCrossfade),
            value: model.content,
        )
        .task { await model.run() }
    }
}

#Preview("Event and topic") {
    StatusLineView(model: StatusLinePreviewData.eventAndTopic).padding()
}

#Preview("Topic only") {
    StatusLineView(model: StatusLinePreviewData.topicOnly).padding()
}

#Preview("Quiet") {
    StatusLineView(model: StatusLinePreviewData.quiet).padding()
}

#Preview("Long, 320 pt") {
    StatusLineView(model: StatusLinePreviewData.long)
        .padding()
        .frame(width: DesignLock.Window.minimumWidth)
}

#Preview("Event and topic, dark") {
    StatusLineView(model: StatusLinePreviewData.eventAndTopic)
        .padding()
        .preferredColorScheme(.dark)
}
