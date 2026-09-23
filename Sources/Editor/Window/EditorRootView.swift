import SwiftUI

struct EditorActions {
    var copy: () -> Void
    var save: () -> Void
    var pin: () -> Void
    var done: () -> Void
    /// nil when the image has no file in the screenshots folder
    var reveal: (() -> Void)?
    /// The name shared files get (the screenshot's file name)
    var shareFilename: String
}

struct EditorRootView: View {
    /// Small enough for any Mac screen, wide enough for both toolbar rows
    static let minimumSize = CGSize(width: 1080, height: 520)
    /// Height of the two toolbar rows with their dividers
    static let toolbarHeight: CGFloat = 94

    @Bindable var model: EditorViewModel
    let actions: EditorActions

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(model: model, actions: actions)
            Divider()
            EditorToolOptionsBar(model: model)
            Divider()
            EditorCanvasContainer(model: model) { command in
                switch command {
                case .copy: actions.copy()
                case .save: actions.save()
                case .done: actions.done()
                }
            }
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    }
}

// MARK: - Main row: undo, tools, result actions

struct EditorToolbar: View {
    @Bindable var model: EditorViewModel
    let actions: EditorActions

    var body: some View {
        HStack(spacing: 4) {
            EditorIconButton(titleKey: "editor.undo", systemImage: "arrow.uturn.backward") { model.undo() }
            EditorIconButton(titleKey: "editor.redo", systemImage: "arrow.uturn.forward") { model.redo() }

            ForEach(Array(AnnotationTool.groups.enumerated()), id: \.offset) { _, group in
                EditorToolbarDivider()
                HStack(spacing: 2) {
                    ForEach(group, id: \.self) { tool in
                        EditorToolButton(tool: tool, isSelected: model.tool == tool) {
                            model.tool = tool
                        }
                    }
                }
            }

            Spacer(minLength: 16)

            EditorIconButton(titleKey: "card.copy", systemImage: "doc.on.doc", action: actions.copy)
            ShareLink(
                item: EditorShareItem(document: model.document, base: model.base, filename: actions.shareFilename),
                preview: SharePreview(actions.shareFilename)
            ) {
                EditorIconLabel(systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .help(L10n("editor.share"))
            .accessibilityLabel(L10n("editor.share"))
            if let reveal = actions.reveal {
                EditorIconButton(titleKey: "card.showInFinder", systemImage: "folder", action: reveal)
            }
            EditorIconButton(titleKey: "card.pin", systemImage: "pin", action: actions.pin)
            EditorIconButton(titleKey: "common.save", systemImage: "square.and.arrow.down", action: actions.save)
                .keyboardShortcut("s", modifiers: .command)
            Button(action: actions.done) {
                Text(L10n("common.done"))
                    .padding(.horizontal, 6)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.leading, 6)
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
    }
}

// MARK: - Options row: what the current tool draws with

struct EditorToolOptionsBar: View {
    @Bindable var model: EditorViewModel

    /// With the selection tool, the options restyle what is selected
    private var options: [AnnotationTool.Option] {
        guard model.tool == .select else { return model.tool.options }
        return model.selection.isEmpty ? [] : [.color, .thickness]
    }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: model.tool.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(L10n(model.tool.titleKey))
                    .font(.system(size: 13, weight: .semibold))
                Text(String(model.tool.shortcut).uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.45), lineWidth: 1))
            }
            .frame(minWidth: 150, alignment: .leading)

            if options.contains(.color) {
                EditorToolbarDivider()
                EditorColorPalette(model: model)
            }
            if options.contains(.thickness) || options.contains(.size) {
                EditorToolbarDivider()
                EditorWeightPicker(model: model, showsTextSize: options.contains(.size))
            }

            Spacer(minLength: 8)

            if model.document.crop != nil {
                Button {
                    model.resetCrop()
                } label: {
                    Label(L10n("editor.resetCrop"), systemImage: "crop.rotate")
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(Color.primary.opacity(0.03))
    }
}

private struct EditorColorPalette: View {
    @Bindable var model: EditorViewModel

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(RGBAColor.palette.enumerated()), id: \.offset) { index, color in
                let isSelected = model.color == color
                Button {
                    model.color = color
                } label: {
                    Circle()
                        .fill(Color(cgColor: color.cgColor))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.primary.opacity(0.35), lineWidth: 1))
                        .padding(3)
                        .overlay(Circle().stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help("\(index + 1)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Three weights drawn as what they produce: line thickness, or letter size for text.
private struct EditorWeightPicker: View {
    @Bindable var model: EditorViewModel
    let showsTextSize: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(L10n(showsTextSize ? "editor.size" : "editor.weight"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(Array(EditorViewModel.Weight.allCases.enumerated()), id: \.offset) { index, weight in
                    let isSelected = model.weight == weight
                    Button {
                        model.weight = weight
                    } label: {
                        sample(index)
                            .frame(width: 34, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1)
                            )
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(index == 0 ? "[" : (index == 2 ? "]" : ""))
                }
            }
        }
    }

    @ViewBuilder
    private func sample(_ index: Int) -> some View {
        if showsTextSize {
            Text("A")
                .font(.system(size: [11, 14, 18][index], weight: .semibold))
        } else {
            Capsule()
                .fill(Color.primary)
                .frame(width: 18, height: [1.5, 3, 5][index])
        }
    }
}

// MARK: - Buttons

private struct EditorToolButton: View {
    let tool: AnnotationTool
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 36, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.08) : .clear))
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(L10n(tool.titleKey)) (\(String(tool.shortcut).uppercased()))")
        .accessibilityLabel(L10n(tool.titleKey))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct EditorIconButton: View {
    let titleKey: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EditorIconLabel(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .help(L10n(titleKey))
        .accessibilityLabel(L10n(titleKey))
    }
}

/// The look of the secondary buttons (also the Share menu's label).
private struct EditorIconLabel: View {
    let systemImage: String

    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(.primary)
            .frame(width: 34, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(.rect)
            .onHover { isHovered = $0 }
    }
}

private struct EditorToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 5)
    }
}
