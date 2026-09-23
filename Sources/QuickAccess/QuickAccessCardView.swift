import SwiftUI

struct QuickAccessCardView: View {
    /// macOS 26–27 geometry: continuous corners, the image concentric inside the glass
    static let cornerRadius: CGFloat = 20
    static let imageInset: CGFloat = 6

    let entry: QuickAccessEntry
    let controller: QuickAccessController
    let actions: QuickAccessActions

    @State private var isHovered = false

    private var imageShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius - Self.imageInset, style: .continuous)
    }

    var body: some View {
        ZStack {
            imageLayer
            if isHovered {
                hoverControls
                    .transition(.opacity)
            }
        }
        .padding(Self.imageInset)
        .frame(width: QuickAccessPresenter.cardSize.width, height: QuickAccessPresenter.cardSize.height)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
            controller.setHovered(entry.id, hovering)
        }
        .draggable(ClipImageTransferable(item: entry.item)) {
            if let thumbnail = entry.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160)
                    .clipShape(imageShape)
            }
        }
        .contextMenu {
            Button(L10n("card.copy")) { copy() }
            Button(L10n("card.annotate")) { annotate() }
            Button(L10n("card.saveAs")) { saveAs() }
            Button(L10n("card.pin")) { pin() }
            Button(L10n("card.copyText")) { actions.copyText(entry.item) }
            if entry.item.savedFilePath != nil {
                Button(L10n("card.showInFinder")) { actions.reveal(entry.item) }
            }
            Divider()
            Button(L10n("common.close")) { controller.dismiss(entry.id) }
            Button(L10n("quickAccess.closeAll")) { controller.dismissAll() }
        }
    }

    /// The screenshot, whole, on a dark letterbox where its shape differs from the card's.
    private var imageLayer: some View {
        ZStack {
            imageShape.fill(.black.opacity(0.35))
            if let thumbnail = entry.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
            }
        }
        .clipShape(imageShape)
        .overlay(imageShape.strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
    }

    private var hoverControls: some View {
        ZStack {
            imageShape.fill(.black.opacity(0.35))

            VStack(spacing: 6) {
                pillButton(L10n("card.copy"), action: copy)
                pillButton(L10n("card.annotate"), action: annotate)
                pillButton(L10n("card.saveAs"), action: saveAs)
            }

            VStack {
                HStack {
                    cornerButton("xmark", help: L10n("common.close")) { controller.dismiss(entry.id) }
                    Spacer()
                    cornerButton("pin.fill", help: L10n("card.pin"), action: pin)
                }
                Spacer()
                HStack {
                    if entry.item.savedFilePath != nil {
                        cornerButton("folder", help: L10n("card.showInFinder")) { actions.reveal(entry.item) }
                    }
                    Spacer()
                    cornerButton("text.viewfinder", help: L10n("card.copyText")) { actions.copyText(entry.item) }
                }
            }
            .padding(5)
        }
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 104)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }

    private func cornerButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .tooltip(help)
        .accessibilityLabel(help)
    }

    private func copy() {
        actions.copy(entry.item)
        controller.dismiss(entry.id)
    }

    private func saveAs() {
        Task { await ImageExporter.saveAs(entry.item) }
    }

    private func annotate() {
        actions.annotate(entry.item)
        controller.dismiss(entry.id)
    }

    private func pin() {
        actions.pin(entry)
        controller.dismiss(entry.id)
    }
}
