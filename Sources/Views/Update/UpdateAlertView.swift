import SwiftUI

struct UpdateAlertView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text(L10n("updateAlert.title"))
                .font(.title2)
                .fontWeight(.bold)

            if case .available(let version) = appState.updater.status {
                Text(L10n("updateAlert.newVersion", version))
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if let current = AppVersion.current {
                    Text(L10n("updateAlert.currentVersion", current.description))
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }

            // Release notes
            if let release = appState.updater.latestRelease, !release.body.isEmpty {
                GroupBox(L10n("updateAlert.whatsNew")) {
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
                    Text(L10n("updateAlert.downloading", Int(progress * 100)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Installing indicator
            if case .installing = appState.updater.status {
                VStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n("updateAlert.installing"))
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
                Button(L10n("updateAlert.later")) {
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
        let cleaned = body
            .components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("SHA256:") && !trimmed.hasPrefix("`") && trimmed != "---"
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // interpretedSyntax preserves line breaks properly
        if let attributed = try? AttributedString(
            markdown: cleaned,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(cleaned)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch appState.updater.status {
        case .available:
            Button(L10n("updateAlert.download")) {
                Task { await appState.updater.downloadUpdate() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

        case .downloading:
            Button(L10n("common.cancel")) {
                appState.updater.cancelDownload()
                dismiss()
            }

        case .readyToInstall:
            Button(L10n("updateAlert.installRestart")) {
                appState.updater.installAndRelaunch()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

        case .error:
            Button(L10n("updateAlert.retry")) {
                Task { await appState.updater.checkForUpdates() }
            }

        default:
            EmptyView()
        }
    }
}
