import SwiftUI
import TownsfolkCore

/// Layout metrics for ``ProfilePopover``, drawn from the design lock.
private enum Layout {
    static let width = DesignLock.Window.profilePopoverWidth
    static let padding = DesignLock.Spacing.large
    static let rowSpacing = DesignLock.Spacing.small
    static let labelGap = DesignLock.Spacing.medium
}

/// A resident's profile (ux-flows S4): the name, "{occupation} · {age group}", and
/// personality; a hairline; the Hobby, Worry, Knows, and Into rows, Knows and Into left
/// out when empty; a hairline; and "Moved in {date}" — or "Moved out {date}", with the
/// name in SecondaryText. 280 pt wide, padded 16, rows 8 apart; every field wraps and is
/// never cut short. Read-only: nothing in it is a control.
struct ProfilePopover: View {
    let profile: ResidentProfile

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.rowSpacing) {
            Text(verbatim: profile.name)
                .font(.headline)
                .foregroundStyle(
                    profile.isPastResident ? AnyShapeStyle(DesignLock.Palette.secondaryText)
                        : AnyShapeStyle(.primary),
                )
            detail(Text(profile.summary))
            detail(Text(verbatim: profile.personality))
            Divider()
            Grid(
                alignment: .leadingFirstTextBaseline,
                horizontalSpacing: Layout.labelGap,
                verticalSpacing: Layout.rowSpacing,
            ) {
                row(ProfileViewModel.hobbyTitle, [Text(verbatim: profile.hobby)])
                row(ProfileViewModel.worryTitle, [Text(verbatim: profile.worry)])
                if !profile.knows.isEmpty {
                    row(ProfileViewModel.knowsTitle, profile.knows.map { Text($0) })
                }
                if !profile.interests.isEmpty {
                    row(ProfileViewModel.intoTitle, profile.interests.map { Text($0) })
                }
            }
            Divider()
            detail(Text(profile.moveLine))
                .accessibilityIdentifier("profileMoveLine")
        }
        .padding(Layout.padding)
        .frame(width: Layout.width, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profilePopover")
    }

    private func detail(_ text: Text) -> some View {
        text
            .font(.callout)
            .foregroundStyle(DesignLock.Palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// One labeled row; the label stands beside the first line, and the rest stack under it.
    private func row(_ label: LocalizedStringResource, _ lines: [Text]) -> some View {
        GridRow {
            detail(Text(label))
                .gridColumnAlignment(.leading)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines.indices, id: \.self) { index in
                    detail(lines[index])
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
