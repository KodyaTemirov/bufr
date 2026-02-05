import SwiftUI

struct HotKeySettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isRecording = false

    var body: some View {
        Form {
            Section("Глобальная горячая клавиша") {
                HStack {
                    Text("Открыть панель")

                    Spacer()

                    if isRecording {
                        Text("Нажмите комбинацию клавиш...")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.accentColor, lineWidth: 1)
                            )
                    } else {
                        Text(appState.hotKeyDisplayString)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(.rect(cornerRadius: 6))
                    }
                }

                HStack {
                    Button(isRecording ? "Отмена" : "Записать новый хоткей") {
                        isRecording.toggle()
                    }

                    if !isRecording {
                        Button("Сбросить") {
                            appState.resetHotKey()
                        }
                    }
                }
            }

            Section {
                Text("Горячая клавиша работает глобально — панель откроется из любого приложения.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
