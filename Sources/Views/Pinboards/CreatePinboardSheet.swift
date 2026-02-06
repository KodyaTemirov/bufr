import SwiftUI

struct CreatePinboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let usedColors: Set<String>
    let onCreate: (String, String?, String?) -> Void

    @State private var name = ""
    @State private var selectedColor = ""

    private let colors = [
        "#007AFF", "#FF3B30", "#FF9500", "#FFCC00",
        "#34C759", "#5AC8FA", "#AF52DE", "#FF2D55",
        "#30B0C7", "#A2845E", "#8E8E93", "#64D2FF",
        "#BF5AF2", "#FF6482", "#32ADE6", "#AC8E68",
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Новая доска")
                .font(.headline)

            TextField("Название", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    guard !name.isEmpty else { return }
                    onCreate(name, nil, selectedColor)
                    dismiss()
                }

            // Color picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Цвет")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 10), count: 8), spacing: 10) {
                    ForEach(colors, id: \.self) { hex in
                        let isUsed = usedColors.contains(hex)
                        Button {
                            if !isUsed {
                                selectedColor = hex
                            }
                        } label: {
                            Circle()
                                .fill(Color(nsColor: ColorExtractor.parseHexColor(hex) ?? .controlAccentColor))
                                .frame(width: 28, height: 28)
                                .opacity(isUsed ? 0.3 : 1)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColor == hex ? 2.5 : 0)
                                        .padding(selectedColor == hex ? -3 : 0)
                                )
                                .overlay {
                                    if isUsed {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
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
        .onAppear {
            selectedColor = colors.first { !usedColors.contains($0) } ?? colors[0]
        }
    }
}
