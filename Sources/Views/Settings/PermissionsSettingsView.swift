import AppKit
import SwiftUI

struct PermissionsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let permissions = appState.permissions

        Form {
            Section {
                statusRow(
                    granted: permissions.screenCapture == .granted,
                    text: screenCaptureStatusText(permissions.screenCapture)
                )
                Text(L10n("permissions.screen.why"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    if permissions.screenCapture == .notRequested {
                        Button(L10n("permissions.request")) { permissions.requestScreenCapture() }
                    } else if permissions.screenCapture != .granted {
                        Button(L10n("permission.guide.openSettings")) { permissions.openScreenCaptureSettings() }
                    }
                    if permissions.screenCapture == .lostAfterUpdate || permissions.screenCapture == .denied {
                        Button(L10n("permission.guide.reset")) {
                            permissions.resetScreenCapturePermission()
                            permissions.requestScreenCapture()
                        }
                    }
                    Spacer()
                    Button(L10n("permission.guide.relaunch")) { AppRelauncher.relaunch() }
                }
            } header: {
                Label(L10n("screenshots.permission.header"), systemImage: "record.circle")
            }

            Section {
                statusRow(
                    granted: permissions.accessibilityGranted,
                    text: L10n(permissions.accessibilityGranted ? "permission.status.granted" : "permission.status.denied")
                )
                Text(L10n("permissions.accessibility.why"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !permissions.accessibilityGranted {
                    HStack {
                        Button(L10n("permissions.request")) { permissions.requestAccessibility() }
                        Button(L10n("permission.guide.openSettings")) { permissions.openAccessibilitySettings() }
                    }
                }
            } header: {
                Label(L10n("permissions.accessibility.header"), systemImage: "accessibility")
            }

            Section {
                Text(L10n("permissions.adhocNote"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L10n("setup.open")) { ScreenshotSetupWindowController.shared.show() }
            }
        }
        .formStyle(.grouped)
        .onAppear { permissions.refresh() }
        // Coming back from System Settings
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private func statusRow(granted: Bool, text: String) -> some View {
        Label(text, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .foregroundStyle(granted ? .green : .orange)
    }

    private func screenCaptureStatusText(_ status: ScreenCapturePermission) -> String {
        switch status {
        case .granted: L10n("permission.status.granted")
        case .notRequested: L10n("permission.status.notRequested")
        case .denied: L10n("permission.status.denied")
        case .lostAfterUpdate: L10n("permission.status.lostAfterUpdate")
        }
    }
}
