import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var confirmClearHistory = false
    @State private var confirmDeleteBoards = false
    @State private var confirmDeleteAll = false
    @State private var exportImportError: String?
    @State private var showExportImportError = false
    @State private var successMessage: String?
    @State private var showSuccess = false

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

            Section("Доски") {
                Button("Экспортировать все доски") {
                    exportAllBoards()
                }
                .disabled(appState.pinboardStore.pinboards.isEmpty)

                Button("Импортировать доски...") {
                    importAllBoards()
                }
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
        .alert("Ошибка", isPresented: $showExportImportError) {
            Button("OK") {}
        } message: {
            Text(exportImportError ?? "")
        }
        .alert("Готово", isPresented: $showSuccess) {
            Button("OK") {}
        } message: {
            Text(successMessage ?? "")
        }
    }

    private func exportAllBoards() {
        Task {
            do {
                let url = try await PinboardExportService.exportAllPinboards(
                    pinboards: appState.pinboardStore.pinboards,
                    database: appState.database,
                    imageStorage: ImageStorage.shared
                )
                successMessage = "Экспортировано в \(url.path)"
                showSuccess = true
            } catch {
                exportImportError = error.localizedDescription
                showExportImportError = true
            }
        }
    }

    private func importAllBoards() {
        Task {
            do {
                let imported = try await PinboardExportService.importAllPinboards(
                    database: appState.database,
                    pinboardStore: appState.pinboardStore,
                    imageStorage: ImageStorage.shared
                )
                if !imported.isEmpty {
                    let names = imported.map { "«\($0.name)»" }.joined(separator: ", ")
                    successMessage = "Импортировано досок: \(imported.count) — \(names)"
                    showSuccess = true
                }
            } catch {
                exportImportError = error.localizedDescription
                showExportImportError = true
            }
        }
    }
}
