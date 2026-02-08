import SwiftUI

struct AboutSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var confirmDeleteAll = false

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
                            Text(L10n("about.version", version.description))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }

                Link(L10n("about.website"), destination: URL(string: "https://bufr.uz/")!)
                Link("GitHub", destination: URL(string: "https://github.com/KodyaTemirov/bufr")!)
                Link(L10n("about.support"), destination: URL(string: "https://tirikchilik.uz/kodyatemirov")!)
            } header: {
                Label(L10n("about.header"), systemImage: "info.circle")
            }

            // MARK: - Удаление данных
            Section {
                Button(L10n("about.deleteAll")) {
                    confirmDeleteAll = true
                }
                .foregroundStyle(.red)
            } header: {
                Label(L10n("about.deleteData.header"), systemImage: "trash")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(L10n("about.deleteAll.confirm.title"), isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button(L10n("about.deleteAll.confirm.action"), role: .destructive) {
                appState.deleteAllBoards()
                appState.clearHistory()
            }
        } message: {
            Text(L10n("about.deleteAll.confirm.message"))
        }
    }
}
