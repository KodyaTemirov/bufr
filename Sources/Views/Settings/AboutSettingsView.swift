import SwiftUI

struct AboutSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var confirmDeleteBoards = false
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

            // MARK: - Удаление данных
            Section {
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
