import SwiftUI

struct ExclusionsSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showAppPicker = false
    @State private var selection: Set<String> = []

    var body: some View {
        Form {
            Section {
                Text(L10n("exclusions.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appState.exclusionManager.excludedApps.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text(L10n("exclusions.empty"))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                } else {
                    List(appState.exclusionManager.excludedApps, selection: $selection) { app in
                        ExcludedAppRow(app: app)
                    }
                    .frame(height: 200)
                }

                HStack {
                    Button {
                        showAppPicker = true
                    } label: {
                        Label(L10n("exclusions.add"), systemImage: "plus")
                    }

                    if !selection.isEmpty {
                        Button(role: .destructive) {
                            removeSelected()
                        } label: {
                            Label(L10n("exclusions.remove"), systemImage: "minus")
                        }
                    }
                }
            } header: {
                Label(L10n("exclusions.header"), systemImage: "eye.slash")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAppPicker) {
            AppPickerSheet { bundleId, appName in
                try? appState.exclusionManager.addExclusion(
                    bundleId: bundleId,
                    appName: appName
                )
            }
        }
    }

    private func removeSelected() {
        for bundleId in selection {
            try? appState.exclusionManager.removeExclusion(bundleId: bundleId)
        }
        selection.removeAll()
    }
}

// MARK: - Excluded App Row

private struct ExcludedAppRow: View {
    let app: ExcludedApp

    var body: some View {
        HStack(spacing: 8) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app")
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading) {
                Text(app.appName)
                    .font(.body)
                Text(app.bundleId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
