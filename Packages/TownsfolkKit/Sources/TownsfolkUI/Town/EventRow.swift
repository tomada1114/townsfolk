import SwiftUI
import TownsfolkCore

/// Layout metrics for ``EventRow``, drawn from the design lock.
private enum Layout {
    static let gap = DesignLock.Spacing.extraSmall
    static let gutter = DesignLock.Timeline.gutter
}

/// An event or a move on one line: its symbol in the gutter, its text — cut short before
/// the time is — and its time, set apart from the groups with no thread line. It cannot
/// be selected or replied to.
struct EventRow: View {
    let row: TimelineEventRow
    let model: TimelineViewModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.gap) {
            Text(verbatim: row.text)
                .lineLimit(1)
            Text(verbatim: "·")
            Text(verbatim: model.time(of: row.startsAt))
                .fixedSize()
                .help(model.fullTime(of: row.startsAt))
        }
        .padding(.leading, Layout.gutter)
        .overlay(alignment: .topLeading) {
            if let symbol = row.symbol {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            }
        }
        .font(.callout)
        .foregroundStyle(DesignLock.Palette.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.reading(of: row)))
        .accessibilityIdentifier("eventRow")
    }
}
