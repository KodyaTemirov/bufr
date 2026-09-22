import SwiftUI

struct QuickAccessCardView: View {
    let entry: QuickAccessEntry
    let controller: QuickAccessController
    let actions: QuickAccessActions

    @State private var isHovered = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)

            if let thumbnail = entry.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            }

            if isHovered {
                hoverControls
                    .transition(.opacity)
            }
        }
        .frame(width: QuickAccessPresenter.cardSize.width, height: QuickAccessPresenter.cardSize.height)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
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
            }
        }
        .contextMenu {
            Button(L10n("card.copy")) { copy() }
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

    private var hoverControls: some View {
        ZStack {
            Color.black.opacity(0.45)

            VStack(spacing: 6) {
                pillButton(L10n("card.copy"), action: copy)
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
            .padding(6)
        }
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 120, height: 26)
                .background(.white, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func cornerButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.black.opacity(0.6), in: .circle)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func copy() {
        actions.copy(entry.item)
        controller.dismiss(entry.id)
    }

    private func saveAs() {
        Task { await ImageExporter.saveAs(entry.item) }
    }

    private func pin() {
        actions.pin(entry)
        controller.dismiss(entry.id)
    }
}
