import SwiftUI

struct UpdateAlertView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Доступно обновление")
                .font(.title2)
                .fontWeight(.bold)

            if case .available(let version) = appState.updater.status {
                Text("Новая версия: \(version)")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if let current = AppVersion.current {
                    Text("Текущая версия: \(current.description)")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }

            // Release notes
            if let release = appState.updater.latestRelease, !release.body.isEmpty {
                GroupBox("Что нового") {
                    ScrollView {
                        Text(markdownBody(release.body))
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                }
            }

            // Download progress
            if case .downloading(let progress) = appState.updater.status {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                    Text("Загрузка... \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Installing indicator
            if case .installing = appState.updater.status {
                VStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Установка...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Error display
            if case .error(let msg) = appState.updater.status {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            // Action buttons
            HStack {
                Button("Позже") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                actionButtons
            }
        }
        .padding(24)
        .frame(width: 420, height: 350)
    }

    private func markdownBody(_ body: String) -> AttributedString {
        // Убираем SHA256 строку и горизонтальную линию из отображения
        let cleaned = body
            .components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("SHA256:") && trimmed != "---"
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let attributed = try? AttributedString(markdown: cleaned) {
            return attributed
        }
        return AttributedString(cleaned)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch appState.updater.status {
        case .available:
            Button("Загрузить и установить") {
                Task { await appState.updater.downloadUpdate() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

        case .downloading:
            Button("Отмена") {
                appState.updater.cancelDownload()
                dismiss()
            }

        case .readyToInstall:
            Button("Установить и перезапустить") {
                appState.updater.installAndRelaunch()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

        case .error:
            Button("Повторить") {
                Task { await appState.updater.checkForUpdates() }
            }

        default:
            EmptyView()
        }
    }
}
