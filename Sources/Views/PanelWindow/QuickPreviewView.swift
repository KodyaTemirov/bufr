import SwiftUI

struct QuickPreviewView: View {
    @Environment(AppState.self) private var appState
    let item: ClipItem
    let onDismiss: () -> Void

    @State private var fullImage: NSImage?
    @State private var isEditing = false
    @State private var editedText: String = ""

    private var isTextType: Bool {
        item.contentType == .text || item.contentType == .richText
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 12) {
                // Header
                HStack {
                    if isTextType {
                        Button {
                            if isEditing {
                                saveEdit()
                            } else {
                                editedText = item.textContent ?? ""
                                isEditing = true
                            }
                        } label: {
                            Label(
                                isEditing ? "Сохранить" : "Редактировать",
                                systemImage: isEditing ? "checkmark.circle" : "pencil"
                            )
                            .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isEditing ? .green : .secondary)

                        if isEditing {
                            Button {
                                isEditing = false
                            } label: {
                                Text("Отмена")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Content
                previewContent
                    .frame(maxWidth: 500, maxHeight: 350)

                // Meta info
                HStack(spacing: 12) {
                    Label(item.contentType.displayName, systemImage: item.contentType.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let app = item.sourceAppName {
                        Text("из \(app)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Text(item.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(20)
            .background(.ultraThickMaterial)
            .clipShape(.rect(cornerRadius: 14))
            .shadow(radius: 20)
            .frame(maxWidth: 540, maxHeight: 420)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.contentType {
        case .text, .richText:
            if isEditing {
                TextEditor(text: $editedText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                ScrollView {
                    Text(item.textContent ?? "")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .clipShape(.rect(cornerRadius: 8))
            }

        case .image:
            imagePreview

        case .url:
            VStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                Text(item.textContent ?? "")
                    .font(.body)
                    .textSelection(.enabled)
                    .foregroundStyle(.blue)
                    .multilineTextAlignment(.center)
            }
            .padding()

        case .file:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(item.filePathsArray, id: \.self) { path in
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.body)
                            .textSelection(.enabled)
                        Spacer()
                        Text(URL(fileURLWithPath: path).deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding()

        case .color:
            let text = item.textContent ?? ""
            VStack(spacing: 12) {
                if let nsColor = ColorExtractor.parseHexColor(text) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: nsColor))
                        .frame(width: 120, height: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                }
                Text(text)
                    .font(.title3.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let fullImage {
            Image(nsImage: fullImage)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 8))
        } else {
            ProgressView()
                .task {
                    if let path = item.imagePath {
                        fullImage = await ImageStorage.shared.loadImage(filename: path)
                    }
                }
        }
    }

    private func saveEdit() {
        guard editedText != item.textContent else {
            isEditing = false
            return
        }
        try? appState.clipItemStore.updateTextContent(item, newText: editedText)
        isEditing = false
    }
}
