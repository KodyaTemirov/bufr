import ServiceManagement
import SwiftUI

private let retentionSteps = [1, 7, 30, 365, 0]

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var confirmClearHistory = false
    @State private var confirmDeleteBoards = false
    @State private var exportImportError: String?
    @State private var showExportImportError = false
    @State private var successMessage: String?
    @State private var showSuccess = false

    var body: some View {
        @Bindable var state = appState

        Form {
            // MARK: - Сохранять историю
            Section {
                LabeledContent {} label: {
                    let retentionLabels = [
                        L10n("general.retention.day"),
                        L10n("general.retention.week"),
                        L10n("general.retention.month"),
                        L10n("general.retention.year"),
                        L10n("general.retention.forever"),
                    ]

                    VStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { Double(retentionSteps.firstIndex(of: state.retentionPeriod) ?? 2) },
                                set: { state.retentionPeriod = retentionSteps[Int($0)] }
                            ),
                            in: 0...Double(retentionSteps.count - 1),
                            step: 1
                        )

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
                }

                Button(L10n("general.retention.clear")) {
                    confirmClearHistory = true
                }
                .foregroundStyle(.red)
            } header: {
                Label(L10n("general.retention.header"), systemImage: "clock.arrow.circlepath")
            }

            // MARK: - Вставка
            Section {
                PasteModeRow(
                    title: L10n("general.paste.activeApp"),
                    description: L10n("general.paste.activeApp.desc"),
                    isSelected: appState.pasteMode == .activeApp
                ) {
                    state.pasteMode = .activeApp
                }

                PasteModeRow(
                    title: L10n("general.paste.clipboard"),
                    description: L10n("general.paste.clipboard.desc"),
                    isSelected: appState.pasteMode == .clipboard
                ) {
                    state.pasteMode = .clipboard
                }

                Toggle(L10n("general.paste.plainText"), isOn: $state.alwaysPastePlainText)
            } header: {
                Label(L10n("general.paste.header"), systemImage: "doc.on.clipboard")
            }

            // MARK: - Панель
            Section {
                Picker(L10n("general.panel.position"), selection: $state.panelPosition) {
                    Text(L10n("general.panel.bottom")).tag(PanelPosition.bottom)
                    Text(L10n("general.panel.top")).tag(PanelPosition.top)
                }
                .pickerStyle(.segmented)
            } header: {
                Label(L10n("general.panel.header"), systemImage: "macwindow")
            }

            // MARK: - Система
            Section {
                Picker(L10n("general.language.picker"), selection: $state.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }

                Toggle(L10n("general.system.launchAtLogin"), isOn: $state.launchAtLogin)

                Toggle(L10n("general.system.playCopySound"), isOn: $state.playCopySound)

                if appState.playCopySound {
                    HStack {
                        Picker(L10n("general.system.copySound"), selection: $state.copySound) {
                            ForEach(CopySound.allCases) { sound in
                                Text(sound.displayName).tag(sound)
                            }
                        }

                        Button {
                            appState.copySound.play()
                        } label: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Label(L10n("general.system.header"), systemImage: "gearshape.2")
            }

            // MARK: - Доски
            Section {
                Button(L10n("general.boards.exportAll")) {
                    exportAllBoards()
                }
                .disabled(appState.pinboardStore.pinboards.isEmpty)

                Button(L10n("general.boards.import")) {
                    importAllBoards()
                }

                Button(L10n("general.boards.deleteAll")) {
                    confirmDeleteBoards = true
                }
                .foregroundStyle(.red)
                .disabled(appState.pinboardStore.pinboards.isEmpty)
            } header: {
                Label(L10n("general.boards.header"), systemImage: "rectangle.on.rectangle.angled")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(L10n("general.retention.confirm.title"), isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button(L10n("general.retention.confirm.action"), role: .destructive) {
                appState.clearHistory()
            }
        } message: {
            Text(L10n("general.retention.confirm.message"))
        }
        .confirmationDialog(L10n("general.boards.confirm.title"), isPresented: $confirmDeleteBoards, titleVisibility: .visible) {
            Button(L10n("general.boards.confirm.action"), role: .destructive) {
                appState.deleteAllBoards()
            }
        } message: {
            Text(L10n("general.boards.confirm.message"))
        }
        .alert(L10n("common.error"), isPresented: $showExportImportError) {
            Button(L10n("common.ok")) {}
        } message: {
            Text(exportImportError ?? "")
        }
        .alert(L10n("common.done"), isPresented: $showSuccess) {
            Button(L10n("common.ok")) {}
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
                successMessage = L10n("common.export.success", url.path)
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
                    successMessage = L10n("common.import.success", imported.count, names)
                    showSuccess = true
                }
            } catch {
                exportImportError = error.localizedDescription
                showExportImportError = true
            }
        }
    }
}

// MARK: - Paste Mode Row

private struct PasteModeRow: View {
    let title: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
