import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            Button("Открыть панель  ⌘⇧V") {
                appState.togglePanel()
            }

            Divider()

            if appState.clipItemStore.items.isEmpty {
                Text("История пуста")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(appState.clipItemStore.items.prefix(10)) { item in
                    MenuBarItemRow(item: item) {
                        copyToClipboard(item)
                    }
                }
            }

            Divider()

            Button("Очистить историю...") {
                appState.clearHistory()
            }
            .keyboardShortcut("K", modifiers: [.command, .shift])

            Divider()

            Button("Настройки...") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Выход") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("Q", modifiers: .command)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
    }

    private var itemLabel: String {
        switch item.contentType {
        case .text, .richText, .url, .color:
            return item.displayText
        case .image:
            return "Изображение"
        case .file:
            let paths = item.filePathsArray
            if let first = paths.first {
                return (first as NSString).lastPathComponent
            }
            return "Файл"
        }
    }
}
