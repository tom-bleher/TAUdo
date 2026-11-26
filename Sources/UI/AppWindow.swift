import AppKit
import SwiftUI

/// TAUdo as a regular window: the panel's tabs with room to spare. Opening TAUdo from Spotlight, Launchpad or
/// Finder shows it. While it's open TAUdo is in the Dock and ⌘-Tab; closed, it lives in the menu bar again.
struct AppWindow: View {
    static let id = "main"

    @Environment(AppModel.self) private var model
    @AppStorage("windowTab") private var tab = PanelView.Tab.due
    @State private var adding = false

    var body: some View {
        ScrollView {
            PanelContent(tab: $tab, adding: $adding)
                .padding(16)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 520, minHeight: 420)
        .toolbar {
            ToolbarItem(placement: .principal) { TabPicker(tab: $tab) }
            ToolbarItemGroup(placement: .primaryAction) { TabActions(tab: $tab, adding: $adding) }
        }
        .navigationSubtitle(subtitle)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            model.refreshIfStale()
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }

    private var subtitle: String {
        if model.syncing { return String(localized: "Syncing…") }
        if let t = model.data.lastSync { return String(localized: "Synced \(t.relative())") }
        return String(localized: "Not synced yet")
    }
}
