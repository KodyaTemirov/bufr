import SwiftUI

struct EditorActions {
    var copy: () -> Void
    var save: () -> Void
    var pin: () -> Void
    var done: () -> Void
}

struct EditorRootView: View {
    /// Small enough for any Mac screen, wide enough for the whole toolbar
    static let minimumSize = CGSize(width: 840, height: 480)

    @Bindable var model: EditorViewModel
    let actions: EditorActions

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(model: model, actions: actions)
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

struct EditorToolbar: View {
    @Bindable var model: EditorViewModel
    let actions: EditorActions

    @State private var showsStyle = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                    Button {
                        model.tool = tool
                    } label: {
                        Image(systemName: tool.systemImage)
                            .frame(width: 26, height: 24)
                            .background(model.tool == tool ? Color.accentColor.opacity(0.22) : .clear, in: .rect(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("\(L10n(tool.titleKey)) (\(String(tool.shortcut).uppercased()))")
                    .accessibilityLabel(L10n(tool.titleKey))
                }
            }

            Divider().frame(height: 22)

            Button {
                showsStyle.toggle()
            } label: {
                Circle()
                    .fill(Color(cgColor: model.color.cgColor))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .help(L10n("editor.style"))
            .accessibilityLabel(L10n("editor.style"))
            .popover(isPresented: $showsStyle, arrowEdge: .bottom) {
                EditorStylePicker(model: model)
                    .padding(12)
            }

            Spacer(minLength: 8)

            if model.document.crop != nil {
                iconButton("editor.resetCrop", systemImage: "crop.rotate") { model.resetCrop() }
            }
            iconButton("editor.undo", systemImage: "arrow.uturn.backward") { model.undo() }
            iconButton("editor.redo", systemImage: "arrow.uturn.forward") { model.redo() }

            Divider().frame(height: 22)

            iconButton("card.copy", systemImage: "doc.on.doc", action: actions.copy)
            iconButton("card.pin", systemImage: "pin", action: actions.pin)
            iconButton("common.save", systemImage: "square.and.arrow.down", action: actions.save)
                .keyboardShortcut("s", modifiers: .command)
            Button(L10n("common.done"), action: actions.done)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func iconButton(_ titleKey: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.borderless)
        .help(L10n(titleKey))
        .accessibilityLabel(L10n(titleKey))
    }
}

/// Colour and thickness, in a popover to keep the toolbar narrow (1–8 and [ ] work too).
private struct EditorStylePicker: View {
    @Bindable var model: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Array(RGBAColor.palette.enumerated()), id: \.offset) { index, color in
                    Button {
                        model.color = color
                    } label: {
                        Circle()
                            .fill(Color(cgColor: color.cgColor))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.primary.opacity(model.color == color ? 0.9 : 0.25), lineWidth: model.color == color ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .help("\(index + 1)")
                }
            }

            Picker(L10n("editor.weight"), selection: $model.weight) {
                Image(systemName: "line.diagonal").tag(EditorViewModel.Weight.thin)
                Image(systemName: "line.diagonal").fontWeight(.semibold).tag(EditorViewModel.Weight.medium)
                Image(systemName: "line.diagonal").fontWeight(.black).tag(EditorViewModel.Weight.thick)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help(L10n("editor.weight"))
        }
    }
}
