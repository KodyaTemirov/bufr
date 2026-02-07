import ServiceManagement
import SwiftUI

private let retentionSteps = [1, 7, 30, 365, 0]
private let retentionLabels = ["День", "Неделя", "Месяц", "Год", "Бесконечно"]

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var confirmClearHistory = false
    @State private var exportImportError: String?
    @State private var showExportImportError = false
    @State private var successMessage: String?
    @State private var showSuccess = false

    var body: some View {
        @Bindable var state = appState

        Form {
            // MARK: - Сохранять историю
            Section {
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { Double(retentionSteps.firstIndex(of: state.retentionPeriod) ?? 2) },
                            set: { state.retentionPeriod = retentionSteps[Int($0)] }
                        ),
                        in: 0...Double(retentionSteps.count - 1),
                        step: 1
                    )
                    .frame(maxWidth: .infinity)

                    HStack {
                        ForEach(retentionLabels.indices, id: \.self) { i in
                            Text(retentionLabels[i])
                                .font(.caption2)
                                .fontWeight(retentionSteps[i] == appState.retentionPeriod ? .semibold : .regular)
                                .foregroundStyle(retentionSteps[i] == appState.retentionPeriod ? .primary : .secondary)
                            if i < retentionLabels.count - 1 { Spacer() }
                        }
                    }
                }

                Button("Стереть историю...") {
                    confirmClearHistory = true
                }
                .foregroundStyle(.red)
            } header: {
                Label("Сохранять историю", systemImage: "clock.arrow.circlepath")
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

            // MARK: - Доски
            Section {
                Button("Экспортировать все доски") {
                    exportAllBoards()
                }
                .disabled(appState.pinboardStore.pinboards.isEmpty)

                Button("Импортировать доски...") {
                    importAllBoards()
                }
            } header: {
                Label("Доски", systemImage: "rectangle.on.rectangle.angled")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Стереть историю?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("Стереть", role: .destructive) {
                appState.clearHistory()
            }
        } message: {
            Text("Вся история копирования будет удалена.")
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
