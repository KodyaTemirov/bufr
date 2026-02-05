import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var confirmClearHistory = false
    @State private var confirmDeleteBoards = false
    @State private var confirmDeleteAll = false

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("История") {
                Stepper(
                    "Лимит истории: \(state.historyLimit)",
                    value: $state.historyLimit,
                    in: 100...50000,
                    step: 100
                )

                Stepper(
                    "Авто-очистка: \(state.autoCleanupDays) дней",
                    value: $state.autoCleanupDays,
                    in: 1...365
                )
            }

            Section("Панель") {
                Picker("Позиция панели", selection: $state.panelPosition) {
                    Text("Снизу").tag(PanelPosition.bottom)
                    Text("Сверху").tag(PanelPosition.top)
                }
                .pickerStyle(.segmented)
            }

            Section("Система") {
                Toggle("Запуск при старте системы", isOn: $state.launchAtLogin)

                Toggle("Звук при копировании", isOn: $state.playCopySound)
            }

            Section("Удаление данных") {
                Button("Очистить буфер") {
                    confirmClearHistory = true
                }

                Button("Удалить все доски") {
                    confirmDeleteBoards = true
                }

                Button("Удалить всё") {
                    confirmDeleteAll = true
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Очистить буфер?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("Очистить", role: .destructive) {
                appState.clearHistory()
            }
        } message: {
            Text("Вся история копирования будет удалена.")
        }
        .confirmationDialog("Удалить все доски?", isPresented: $confirmDeleteBoards, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                appState.deleteAllBoards()
            }
        } message: {
            Text("Все доски и привязки к ним будут удалены.")
        }
        .confirmationDialog("Удалить всё?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Удалить всё", role: .destructive) {
                appState.deleteAllBoards()
                appState.clearHistory()
            }
        } message: {
            Text("Вся история и все доски будут удалены.")
        }
    }
}
