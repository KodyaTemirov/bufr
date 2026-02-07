import SwiftUI

struct AboutSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var confirmClearHistory = false
    @State private var confirmDeleteBoards = false
    @State private var confirmDeleteAll = false
    @State private var exportImportError: String?
    @State private var showExportImportError = false
    @State private var successMessage: String?
    @State private var showSuccess = false

    var body: some View {
        Form {
            // MARK: - О приложении
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                        .clipShape(.rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bufr")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                        if let version = AppVersion.current {
                            Text("Версия \(version.description)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }

                Link("GitHub", destination: URL(string: "https://github.com/KodyaTemirov/bufr")!)
                Link("Поддержать разработчика", destination: URL(string: "https://tirikchilik.uz/kodyatemirov")!)
            } header: {
                Label("О приложении", systemImage: "info.circle")
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

            // MARK: - Удаление данных
            Section {
                Button("Очистить буфер") {
                    confirmClearHistory = true
                }
                .foregroundStyle(.red)

                Button("Удалить все доски") {
                    confirmDeleteBoards = true
                }
                .foregroundStyle(.red)

                Button("Удалить всё") {
                    confirmDeleteAll = true
                }
                .foregroundStyle(.red)
            } header: {
                Label("Удаление данных", systemImage: "trash")
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
