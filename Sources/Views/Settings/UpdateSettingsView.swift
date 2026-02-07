import SwiftUI

struct UpdateSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showUpdateSheet = false

    var body: some View {
        @Bindable var state = appState

        Form {
            Section {
                Toggle("Проверять автоматически", isOn: Bindable(state).updater.autoCheckEnabled)

                HStack {
                    Button("Проверить обновления") {
                        Task { await appState.updater.checkForUpdates() }
                    }
                    .disabled(appState.updater.status == .checking)

                    Spacer()

                    updateStatusView
                }

                if let lastCheck = appState.updater.lastCheckDate {
                    Text("Последняя проверка: \(lastCheck, style: .relative) назад")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Label("Обновления", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showUpdateSheet) {
            UpdateAlertView()
                .environment(appState)
        }
        .onChange(of: appState.updater.status) { _, newStatus in
            if case .available = newStatus {
                showUpdateSheet = true
            }
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch appState.updater.status {
        case .checking:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Проверка...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .noUpdate:
            Text("Установлена последняя версия")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .available(let version):
            Button("Версия \(version) доступна") {
                showUpdateSheet = true
            }
            .font(.caption)
        case .error(let msg):
            Text(msg)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        default:
            EmptyView()
        }
    }
}
