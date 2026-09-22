import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @State private var menuItems: [ClipItem] = []

    var body: some View {
        // Reading appLanguage forces SwiftUI to re-render on language change
        let _ = appState.appLanguage
        VStack(spacing: 0) {
            ForEach(Self.captureActions, id: \.action) { entry in
                Button(L10n(entry.action.titleKey)) {
                    AppState.shared.screenshots.capture(entry.mode, afterMenuCloses: true)
                }
                .keyboardShortcut(menuShortcut(for: entry.action))
            }

            Button(L10n("menubar.capture.openFolder")) {
                AppState.shared.screenshots.openScreenshotsFolder()
            }

            // Locked pins ignore the mouse; this is the way to unlock or close them
            if appState.pins.hasPins {
                Menu(L10n("menubar.pins")) {
                    Button(L10n("menubar.pins.unlockAll")) {
                        AppState.shared.pins.unlockAll()
                    }
                    Button(L10n("screenPin.closeAll")) {
                        AppState.shared.pins.closeAll()
                    }
                }
            }

            if appState.permissions.screenCapture != .granted {
                Button(L10n("menubar.capture.permission")) {
                    PermissionGuideWindowController.shared.show()
                }
            }

            Divider()

            Button(L10n("menubar.openPanel")) {
                AppState.shared.togglePanel()
            }
            .keyboardShortcut(appState.hotKeyManager.bindings[.togglePanel]?.keyboardShortcut)

            Divider()

            if menuItems.isEmpty {
                Text(L10n("menubar.historyEmpty"))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(menuItems.enumerated()), id: \.element.id) { index, item in
                    MenuBarItemRow(item: item, shortcutIndex: index < 9 ? index + 1 : nil) {
                        AppState.shared.copyItem(item)
                    }
                }
            }

            Divider()

            Button(L10n("menubar.clearHistory")) {
                AppState.shared.clearHistory()
                menuItems = []
            }
            .keyboardShortcut("K", modifiers: [.command, .shift])

            Divider()

            Button(L10n("menubar.checkUpdates")) {
                Task {
                    await AppState.shared.updater.checkForUpdates()
                }
                SettingsWindowController.shared.show(tab: .updates)
            }

            Divider()

            Button(L10n("menubar.settings")) {
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button(L10n("menubar.support")) {
                if let url = URL(string: "https://tirikchilik.uz/kodyatemirov") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            Button(L10n("menubar.quit")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("Q", modifiers: .command)
        }
        .onAppear {
            menuItems = Array(AppState.shared.clipItemStore.items.prefix(10))
            AppState.shared.permissions.refresh()
        }
    }

    private static let captureActions: [(action: HotKeyAction, mode: CaptureMode)] = [
        (.captureArea, .area),
        (.captureWindow, .window),
        (.captureFullscreen, .fullscreen),
        (.capturePreviousArea, .previousArea),
        (.captureAllInOne, .allInOne),
        (.captureText, .text),
    ]

    /// A shortcut macOS still owns would be misleading next to the item
    private func menuShortcut(for action: HotKeyAction) -> KeyboardShortcut? {
        appState.hotKeyManager.activeBinding(for: action)?.keyboardShortcut
    }
}

// MARK: - Menu Item Row

private struct MenuBarItemRow: View {
    let item: ClipItem
    var shortcutIndex: Int? = nil
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: item.contentType.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(itemLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text(item.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }

        if let index = shortcutIndex {
            button.keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
        } else {
            button
        }
    }

    private var itemLabel: String {
        switch item.contentType {
        case .text, .richText, .url, .color:
            return item.displayText
        case .image:
            return L10n("menubar.image")
        case .file:
            let paths = item.filePathsArray
            if let first = paths.first {
                return (first as NSString).lastPathComponent
            }
            return L10n("menubar.file")
        }
    }
}
