import AppKit
import SwiftUI

struct AppPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String, String) -> Void

    @State private var searchText = ""
    @State private var installedApps: [AppInfo] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Выберите приложение")
                    .font(.headline)
                Spacer()
                Button("Закрыть") {
                    dismiss()
                }
            }
            .padding()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Поиск...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05))
            .clipShape(.rect(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.bottom, 8)

            // App list
            List(filteredApps) { app in
                Button {
                    onSelect(app.bundleId, app.name)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading) {
                            Text(app.name)
                                .font(.body)
                            Text(app.bundleId)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 400, height: 500)
        .task {
            installedApps = Self.loadInstalledApps()
        }
    }

    // Pre-filtered results (not inline in ForEach per SwiftUI best practices)
    private var filteredApps: [AppInfo] {
        if searchText.isEmpty {
            return installedApps
        }
        return installedApps.filter {
            $0.name.localizedStandardContains(searchText)
            || $0.bundleId.localizedStandardContains(searchText)
        }
    }

    // MARK: - Load Apps

    private static func loadInstalledApps() -> [AppInfo] {
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]

        var apps: [AppInfo] = []
        let workspace = NSWorkspace.shared

        for dir in appDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else { continue }

            for url in contents where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleId = bundle.bundleIdentifier
                else { continue }

                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent

                let icon = workspace.icon(forFile: url.path)

                apps.append(AppInfo(
                    bundleId: bundleId,
                    name: name,
                    icon: icon
                ))
            }
        }

        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - AppInfo

private struct AppInfo: Identifiable {
    let bundleId: String
    let name: String
    let icon: NSImage
    var id: String { bundleId }
}
