import SwiftUI

struct EditorActions {
    var copy: () -> Void
    var save: () -> Void
    var pin: () -> Void
    var done: () -> Void
}

struct EditorRootView: View {
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
        .frame(minWidth: 640, minHeight: 420)
    }
}

private struct EditorToolbar: View {
    @Bindable var model: EditorViewModel
    let actions: EditorActions

    var body: some View {
        HStack(spacing: 10) {
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
                }
            }

            Divider().frame(height: 22)

            HStack(spacing: 5) {
                ForEach(Array(RGBAColor.palette.enumerated()), id: \.offset) { index, color in
                    Button {
                        model.color = color
                    } label: {
                        Circle()
                            .fill(Color(cgColor: color.cgColor))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.primary.opacity(model.color == color ? 0.9 : 0.25), lineWidth: model.color == color ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .help("\(index + 1)")
                }
            }

            Picker("", selection: $model.weight) {
                Image(systemName: "line.diagonal").tag(EditorViewModel.Weight.thin)
                Image(systemName: "line.diagonal").fontWeight(.semibold).tag(EditorViewModel.Weight.medium)
                Image(systemName: "line.diagonal").fontWeight(.black).tag(EditorViewModel.Weight.thick)
            }
            .pickerStyle(.segmented)
            .frame(width: 110)
            .help(L10n("editor.weight"))

            Spacer(minLength: 8)

            if model.document.crop != nil {
                Button(L10n("editor.resetCrop")) { model.resetCrop() }
            }

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .help(L10n("editor.undo"))
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .help(L10n("editor.redo"))

            Button(L10n("card.copy"), action: actions.copy)
            Button(L10n("card.pin"), action: actions.pin)
            Button(L10n("common.save"), action: actions.save)
                .keyboardShortcut("s", modifiers: .command)
            Button(L10n("common.done"), action: actions.done)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
