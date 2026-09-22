import SwiftUI

/// Shown while an enabled macOS screenshot shortcut blocks one of Bufr's capture hotkeys.
struct SystemShortcutsBanner: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n("hotkeys.system.title"), systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(L10n("hotkeys.system.text"))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(L10n("hotkeys.system.open")) {
                    appState.permissions.openKeyboardShortcutsSettings()
                }
                Button(L10n("hotkeys.system.recheck")) {
                    appState.hotKeyManager.recheckSystemConflicts()
                }
            }
        }
        .padding(.vertical, 4)
    }
}
