import SwiftUI

struct UpdateSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showUpdateSheet = false

    var body: some View {
        @Bindable var state = appState

        Form {
            Section {
                Toggle(L10n("updates.autoCheck"), isOn: Bindable(state).updater.autoCheckEnabled)

                HStack {
                    Button(L10n("updates.checkNow")) {
                        Task { await appState.updater.checkForUpdates() }
                    }
                    .disabled(appState.updater.status == .checking)

                    Spacer()

                    updateStatusView
                }

                if let lastCheck = appState.updater.lastCheckDate {
                    HStack(spacing: 0) {
                        Text(L10n("updates.lastCheck"))
                        Text(lastCheck, style: .relative)
                        Text(L10n("updates.lastCheck.suffix"))
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            } header: {
                Label(L10n("updates.header"), systemImage: "arrow.triangle.2.circlepath")
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
                Text(L10n("updates.checking"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .noUpdate:
            Text(L10n("updates.upToDate"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .available(let version):
            Button(L10n("updates.available", version)) {
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
