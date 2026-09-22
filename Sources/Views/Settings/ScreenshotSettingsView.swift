import AppKit
import SwiftUI

struct ScreenshotSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var ocrProgress: OCRRepository.Progress?

    var body: some View {
        @Bindable var settings = appState.screenshotSettings

        Form {
            Section {
                LabeledContent(L10n("screenshots.folder")) {
                    HStack {
                        Text((settings.saveFolder.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button(L10n("screenshots.folder.choose")) {
                            chooseFolder()
                        }
                    }
                }

                HStack {
                    Button(L10n("screenshots.folder.show")) {
                        appState.screenshots.openScreenshotsFolder()
                    }
                    Button(L10n("screenshots.folder.reset")) {
                        settings.resetSaveFolder()
                    }
                    .disabled(settings.saveFolder.standardizedFileURL == ScreenshotSettings.defaultSaveFolder.standardizedFileURL)
                }

                TextField(
                    L10n("screenshots.filename.prefix"),
                    text: Binding(
                        get: { settings.customFilenamePrefix ?? "" },
                        set: { settings.customFilenamePrefix = $0.isEmpty ? nil : $0 }
                    ),
                    prompt: Text(L10n("screenshot.filename.prefix"))
                )

                Text(L10n("screenshots.filename.preview", filenamePreview))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label(L10n("screenshots.saving.header"), systemImage: "folder")
            }

            Section {
                Picker(L10n("screenshots.afterCapture.action"), selection: $settings.afterCapture) {
                    ForEach(AfterCaptureAction.allCases, id: \.self) { action in
                        Text(L10n("screenshots.afterCapture.\(action.rawValue)")).tag(action)
                    }
                }

                if settings.afterCapture == .quickAccess {
                    Picker(L10n("screenshots.quickAccess.position"), selection: $settings.quickAccessPosition) {
                        Text(L10n("screenshots.quickAccess.bottomLeft")).tag(QuickAccessPosition.bottomLeft)
                        Text(L10n("screenshots.quickAccess.bottomRight")).tag(QuickAccessPosition.bottomRight)
                    }
                    Picker(L10n("screenshots.quickAccess.autoClose"), selection: $settings.quickAccessAutoClose) {
                        ForEach(ScreenshotSettings.autoCloseChoices, id: \.self) { seconds in
                            Text(seconds == 0 ? L10n("screenshots.quickAccess.never") : L10n("screenshots.quickAccess.seconds", seconds))
                                .tag(seconds)
                        }
                    }
                }

                Toggle(L10n("screenshots.copyToClipboard"), isOn: $settings.copyToClipboard)
                Toggle(L10n("screenshots.playSound"), isOn: $settings.playSound)
            } header: {
                Label(L10n("screenshots.afterCapture.header"), systemImage: "checkmark.circle")
            }

            Section {
                Toggle(L10n("screenshots.windowShadow"), isOn: $settings.windowShadow)
                Toggle(L10n("screenshots.includeCursor"), isOn: $settings.includeCursor)
                Toggle(L10n("screenshots.retinaAtOneX"), isOn: $settings.retinaAtOneX)
                Text(L10n("screenshots.tip"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label(L10n("screenshots.capture.header"), systemImage: "camera.viewfinder")
            }

            Section {
                Toggle(L10n("screenshots.ocr.enabled"), isOn: $settings.ocrIndexingEnabled)
                if let ocrProgress, ocrProgress.total > 0 {
                    Text(L10n("screenshots.ocr.progress", ocrProgress.done, ocrProgress.total))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(L10n("screenshots.ocr.reindex")) {
                    Task {
                        await appState.ocrIndexer.reindexAll()
                        ocrProgress = await appState.ocrIndexer.progress()
                    }
                }
                .disabled(!settings.ocrIndexingEnabled)
                Text(L10n("screenshots.ocr.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label(L10n("screenshots.ocr.header"), systemImage: "text.viewfinder")
            }
            .task(id: settings.ocrIndexingEnabled) {
                await appState.ocrIndexer.setEnabled(settings.ocrIndexingEnabled)
                ocrProgress = await appState.ocrIndexer.progress()
            }

            Section {
                HStack {
                    Label(statusText, systemImage: appState.permissions.screenCapture == .granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(appState.permissions.screenCapture == .granted ? .green : .orange)
                    Spacer()
                    if appState.permissions.screenCapture != .granted {
                        Button(L10n("permission.openGuide")) {
                            PermissionGuideWindowController.shared.show()
                        }
                    }
                }
            } header: {
                Label(L10n("screenshots.permission.header"), systemImage: "lock.shield")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            appState.permissions.refresh()
        }
    }

    private var filenamePreview: String {
        ScreenshotFilenameFormatter.baseName(
            prefix: appState.screenshotSettings.filenamePrefix,
            connector: L10n("screenshot.filename.at"),
            date: Date()
        ) + ".png"
    }

    private var statusText: String {
        switch appState.permissions.screenCapture {
        case .granted: L10n("permission.status.granted")
        case .notRequested: L10n("permission.status.notRequested")
        case .denied: L10n("permission.status.denied")
        case .lostAfterUpdate: L10n("permission.status.lostAfterUpdate")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = appState.screenshotSettings.saveFolder
        panel.prompt = L10n("screenshots.folder.panelPrompt")
        if panel.runModal() == .OK, let url = panel.url {
            appState.screenshotSettings.saveFolder = url
        }
    }
}
