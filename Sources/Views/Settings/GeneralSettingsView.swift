import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            // MARK: - История
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Лимит истории")
                        Spacer()
                        Text("\(state.historyLimit)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(state.historyLimit) },
                            set: { state.historyLimit = Int(($0 / 100).rounded() * 100) }
                        ),
                        in: 100...50000
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Авто-очистка")
                        Spacer()
                        Text("\(state.autoCleanupDays) дн.")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(state.autoCleanupDays) },
                            set: { state.autoCleanupDays = Int($0.rounded()) }
                        ),
                        in: 1...365
                    )
                }
            } header: {
                Label("История", systemImage: "clock.arrow.circlepath")
            }

            // MARK: - Панель
            Section {
                Picker("Позиция панели", selection: $state.panelPosition) {
                    Text("Снизу").tag(PanelPosition.bottom)
                    Text("Сверху").tag(PanelPosition.top)
                }
                .pickerStyle(.segmented)
            } header: {
                Label("Панель", systemImage: "macwindow")
            }

            // MARK: - Система
            Section {
                Toggle("Запуск при старте системы", isOn: $state.launchAtLogin)
                Toggle("Звук при копировании", isOn: $state.playCopySound)
            } header: {
                Label("Система", systemImage: "gearshape.2")
            }
        }
        .formStyle(.grouped)
    }
}
