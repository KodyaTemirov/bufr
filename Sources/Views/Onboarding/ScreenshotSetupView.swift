import AppKit
import SwiftUI

/// First launch of 3.0: the three things screenshots need, each with a live checkmark.
struct ScreenshotSetupView: View {
    @Environment(AppState.self) private var appState
    let onClose: () -> Void

    var body: some View {
        let permissions = appState.permissions
        let screenshotShortcutsFree = appState.hotKeyManager.blockedBySystem.isEmpty

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n("setup.title"))
                    .font(.title2.weight(.semibold))
                Text(L10n("setup.subtitle"))
                    .foregroundStyle(.secondary)
            }

            step(1, done: permissions.screenCapture == .granted, title: L10n("setup.permission.title"), text: L10n("setup.permission.text")) {
                if permissions.screenCapture == .notRequested {
                    Button(L10n("permissions.request")) { permissions.requestScreenCapture() }
                } else if permissions.screenCapture != .granted {
                    Button(L10n("permission.guide.openSettings")) { permissions.openScreenCaptureSettings() }
                    Button(L10n("permission.guide.relaunch")) { AppRelauncher.relaunch() }
                }
            }

            step(2, done: screenshotShortcutsFree, title: L10n("setup.shortcuts.title"), text: L10n("hotkeys.system.text")) {
                if !screenshotShortcutsFree {
                    Button(L10n("hotkeys.system.open")) { permissions.openKeyboardShortcutsSettings() }
                    Button(L10n("hotkeys.system.recheck")) { appState.hotKeyManager.recheckSystemConflicts() }
                }
            }

            step(3, done: true, title: L10n("setup.folder.title"),
                 text: L10n("setup.folder.text", (appState.screenshotSettings.saveFolder.path as NSString).abbreviatingWithTildeInPath)) {
                Button(L10n("screenshots.folder.show")) { appState.screenshots.openScreenshotsFolder() }
                Button(L10n("setup.folder.change")) {
                    onClose()
                    SettingsWindowController.shared.show(tab: .screenshots)
                }
            }

            HStack {
                Spacer()
                Button(L10n("setup.later"), action: onClose)
                Button(L10n("common.done"), action: onClose)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 580)
        .task {
            // Checkmarks follow System Settings while this window is open
            while !Task.isCancelled {
                permissions.refresh()
                appState.hotKeyManager.recheckSystemConflicts()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func step(
        _ number: Int, done: Bool, title: String, text: String,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(.body, design: .rounded, weight: .semibold))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack { actions() }
            }
        }
    }
}

@MainActor
final class ScreenshotSetupWindowController {
    static let shared = ScreenshotSetupWindowController()

    private let presenter = SingleWindowPresenter()

    private init() {}

    func show() {
        presenter.show(title: L10n("setup.title")) { close in
            ScreenshotSetupView(onClose: close)
        }
    }
}
