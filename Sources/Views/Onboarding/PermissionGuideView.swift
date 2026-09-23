import AppKit
import SwiftUI

/// Explains how to allow Screen Recording; shown when a capture is attempted without it.
struct PermissionGuideView: View {
    @Environment(AppState.self) private var appState
    let onClose: () -> Void

    private var status: ScreenCapturePermission { appState.permissions.screenCapture }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: status == .granted ? "checkmark.seal.fill" : "record.circle")
                    .font(.system(size: 34))
                    .foregroundStyle(status == .granted ? .green : .red)
                Text(L10n("permission.guide.title"))
                    .font(.title2.weight(.semibold))
            }

            if status == .granted {
                Text(L10n("permission.guide.granted"))
            } else {
                Text(L10n(status == .lostAfterUpdate ? "permission.guide.lostText" : "permission.guide.text"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if status != .granted {
                    Button(L10n("permission.guide.openSettings")) {
                        appState.permissions.openScreenCaptureSettings()
                    }
                    .buttonStyle(.borderedProminent)

                    if status == .lostAfterUpdate || status == .denied {
                        Button(L10n("permission.guide.reset")) {
                            appState.permissions.resetScreenCapturePermission()
                            appState.permissions.requestScreenCapture()
                        }
                    }
                }

                Spacer()

                // macOS applies a new grant only to a newly started process
                Button(L10n("permission.guide.relaunch")) {
                    AppRelauncher.relaunch()
                }

                Button(L10n("common.close")) {
                    onClose()
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .task {
            // Follow the switch in System Settings while this window is open
            while !Task.isCancelled {
                appState.permissions.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

@MainActor
final class PermissionGuideWindowController {
    static let shared = PermissionGuideWindowController()

    private let presenter = SingleWindowPresenter()

    private init() {}

    func show() {
        presenter.show(title: L10n("permission.guide.title")) { close in
            PermissionGuideView(onClose: close)
                .environment(AppState.shared)
        }
    }
}
