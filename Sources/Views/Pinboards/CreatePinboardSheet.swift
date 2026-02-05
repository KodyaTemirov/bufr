import SwiftUI

struct CreatePinboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, String?, String?) -> Void

    @State private var name = ""
    @State private var selectedColor = "#007AFF"

    private let colors = [
        "#007AFF", "#FF3B30", "#FF9500", "#FFCC00",
        "#34C759", "#5AC8FA", "#AF52DE", "#FF2D55",
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Новая доска")
                .font(.headline)

            TextField("Название", text: $name)
                .textFieldStyle(.roundedBorder)

            // Color picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Цвет")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(colors, id: \.self) { hex in
                        Button {
                            selectedColor = hex
                        } label: {
                            Circle()
                                .fill(Color(nsColor: ColorExtractor.parseHexColor(hex) ?? .controlAccentColor))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColor == hex ? 2.5 : 0)
                                        .padding(selectedColor == hex ? -3 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Button("Отмена") {
                    dismiss()
                }

                Spacer()

                Button("Создать") {
                    guard !name.isEmpty else { return }
                    onCreate(name, nil, selectedColor)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
