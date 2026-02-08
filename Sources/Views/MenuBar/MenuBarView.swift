import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @State private var menuItems: [ClipItem] = []

    var body: some View {
        // Reading appLanguage forces SwiftUI to re-render on language change
        let _ = appState.appLanguage
        VStack(spacing: 0) {
            Button(L10n("menubar.openPanel")) {
                AppState.shared.togglePanel()
            }
            .keyboardShortcut("V", modifiers: [.command, .shift])

            Divider()

            if menuItems.isEmpty {
                Text(L10n("menubar.historyEmpty"))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(menuItems.enumerated()), id: \.element.id) { index, item in
                    MenuBarItemRow(item: item, shortcutIndex: index < 9 ? index + 1 : nil) {
                        copyToClipboard(item)
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
                NSApplication.shared.activate()
                openSettings()
            }

            Divider()

            Button(L10n("menubar.settings")) {
                NSApplication.shared.activate()
                openSettings()
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
        }
    }

    private func copyToClipboard(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let text = item.textContent {
            pasteboard.setString(text, forType: .string)
        }
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
