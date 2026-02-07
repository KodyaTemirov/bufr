import SwiftUI

struct HotKeySettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isRecording = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Открыть панель")

                    Spacer()

                    if isRecording {
                        Text("Нажмите комбинацию клавиш...")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor, lineWidth: 1)
                            )
                    } else {
                        Text(appState.hotKeyDisplayString)
                            .font(.system(.title3, design: .monospaced, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.quinary, in: .rect(cornerRadius: 8))
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
            } header: {
                Label("Глобальная горячая клавиша", systemImage: "command")
            }

            Section {
                Text("Горячая клавиша работает глобально — панель откроется из любого приложения.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Подсказка", systemImage: "lightbulb")
            }
        }
        .formStyle(.grouped)
    }
}
