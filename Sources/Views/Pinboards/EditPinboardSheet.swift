import SwiftUI

struct EditPinboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pinboard: Pinboard
    let usedColors: Set<String>
    let onSave: (String, String?) -> Void

    @State private var name: String
    @State private var selectedColor: String

    private let colors = [
        "#007AFF", "#FF3B30", "#FF9500", "#FFCC00",
        "#34C759", "#5AC8FA", "#AF52DE", "#FF2D55",
        "#30B0C7", "#A2845E", "#8E8E93", "#64D2FF",
        "#BF5AF2", "#FF6482", "#32ADE6", "#AC8E68",
    ]

    init(pinboard: Pinboard, usedColors: Set<String>, onSave: @escaping (String, String?) -> Void) {
        self.pinboard = pinboard
        self.usedColors = usedColors
        self.onSave = onSave
        _name = State(initialValue: pinboard.name)
        _selectedColor = State(initialValue: pinboard.color ?? "#007AFF")
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n("pinboard.edit.title"))
                .font(.headline)

            TextField(L10n("pinboard.name"), text: $name)
                .textFieldStyle(.roundedBorder)

            // Color picker
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n("pinboard.color"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 10), count: 8), spacing: 10) {
                    ForEach(colors, id: \.self) { hex in
                        let isUsed = usedColors.contains(hex) && hex != pinboard.color
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
                Button(L10n("common.cancel")) {
                    dismiss()
                }

                Spacer()

                Button(L10n("common.save")) {
                    guard !name.isEmpty else { return }
                    onSave(name, selectedColor)
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
