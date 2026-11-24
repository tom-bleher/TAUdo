import Sparkle
import SwiftUI

/// In-app updates via Sparkle. The feed URL and signing key are in Info.plist (project.yml).
@MainActor @Observable
final class Updates {
    static let shared = Updates()

    private let front = BringToFront()
    private let controller: SPUStandardUpdaterController
    private var updater: SPUUpdater { controller.updater }
    private var observation: NSKeyValueObservation?

    /// False while a check is already running.
    private(set) var canCheck = false
    var checksAutomatically: Bool { didSet { updater.automaticallyChecksForUpdates = checksAutomatically } }
    /// Downloads in the background and installs when TAUdo quits.
    var installsAutomatically: Bool { didSet { updater.automaticallyDownloadsUpdates = installsAutomatically } }

    private init() {
        // `--demo` (screenshots) never checks.
        controller = SPUStandardUpdaterController(startingUpdater: !CommandLine.arguments.contains("--demo"),
                                                  updaterDelegate: nil, userDriverDelegate: front)
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        installsAutomatically = controller.updater.automaticallyDownloadsUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] u, _ in
            let can = u.canCheckForUpdates
            Task { @MainActor in self?.canCheck = can }
        }
    }

    func check() { controller.checkForUpdates(nil) }
}

/// TAUdo lives in the menu bar, so Sparkle would open a scheduled update's window behind other apps.
/// When it would, bring it to the front instead (Sparkle's "gentle reminders" hook).
private final class BringToFront: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        MainActor.assumeIsolated {
            NSApp.activate()
            Updates.shared.check()
        }
    }
}
