import SwiftUI

/// A preferences pane in the classic macOS layout: bold labels in a trailing-aligned column, controls beside them,
/// hairlines between groups. As tall as its content, so each tab gets a window that fits it.
struct Pane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 14) { content }
            .padding(.horizontal, 32).padding(.top, 22).padding(.bottom, 24)
            .frame(width: SettingsView.width)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One labelled row of a pane; its controls stack vertically.
struct Row<Content: View>: View {
    static var labelWidth: CGFloat { 138 }

    let label: Text
    @ViewBuilder var content: Content

    init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = Text(label); self.content = content()
    }

    var body: some View {
        GridRow {
            label.fontWeight(.semibold).multilineTextAlignment(.trailing)
                .frame(minWidth: Self.labelWidth, alignment: .trailing)
                .gridColumnAlignment(.trailing)
            VStack(alignment: .leading, spacing: 7) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The hairline between groups of rows.
struct Rule: View {
    var body: some View { Divider().gridCellUnsizedAxes(.horizontal).padding(.vertical, 3) }
}

/// Small print under a control.
struct Note: View {
    let text: Text
    init(_ key: LocalizedStringKey) { text = Text(key) }
    init(_ text: Text) { self.text = text }

    var body: some View {
        text.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// A coloured dot with a line of status text, e.g. "● Connected".
struct StatusLine: View {
    let color: Color
    let text: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            text.fixedSize(horizontal: false, vertical: true)
        }
    }
}
