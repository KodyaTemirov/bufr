import AppKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.bufr.app", category: "ClipCardView")

struct ClipCardView: View {
    @Environment(AppState.self) private var appState
    let item: ClipItem
    let isSelected: Bool
    var boardColor: Color? = nil
    var shortcutIndex: Int? = nil

    var onRename: ((ClipItem) -> Void)? = nil

    @State private var isHovered = false
    @State private var itemBoardColor: Color?
    @State private var appIconColor: Color?

    private let cardRadius: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            // Compact header: icon + meta on left, app icon on right
            headerRow
                .padding(.horizontal, 12)
                .frame(height: 50)
                .background(headerColor)
                .clipped()

            // Content area
            cardContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            // Footer
            if let footer = footerText {
                Text(footer)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 240, height: 200)
        .background(
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .stroke(
                    (isSelected || isHovered) ? (effectiveBoardColor?.opacity(0.7) ?? Color.accentColor.opacity(0.7)) : .clear,
                    lineWidth: (isSelected || isHovered) ? 2 : 0
                )
        )
        .overlay(alignment: .bottomTrailing) {
            if let index = shortcutIndex {
                Text("⌘\(index)")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(8)
            }
        }
        .shadow(
            color: isHovered ? .black.opacity(0.15) : .black.opacity(0.06),
            radius: isHovered ? 12 : 4,
            y: isHovered ? 4 : 1
        )
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .animation(.spring(duration: 0.25, bounce: 0.2), value: isSelected)
        .onHover { isHovered = $0 }
        .draggable(dragPayload)
        .contextMenu {
            if !appState.pinboardStore.pinboards.isEmpty {
                Menu(L10n("card.addToBoard")) {
                    ForEach(appState.pinboardStore.pinboards) { board in
                        Button {
                            do {
                                try appState.pinboardStore.addClip(item.id, to: board.id)
                            } catch {
                                logger.error("Failed to add clip to board: \(error.localizedDescription, privacy: .public)")
                            }
                        } label: {
                            Label(board.name, systemImage: "circle.fill")
                        }
                        .tint(boardLabelColor(board))
                    }
                }
            }

            Button(L10n("card.copy")) {
                appState.clipboardPaster.copyToClipboard(item)
            }

            Button(L10n("card.rename")) {
                onRename?(item)
            }

            Divider()

            Button(L10n("common.delete"), role: .destructive) {
                appState.deleteItem(item)
            }
        }
        .task {
            lookupBoardColor()
            if let icon = appIcon,
               let dominant = ColorExtractor.dominantColor(from: icon),
               let hsb = dominant.usingColorSpace(.deviceRGB) {
                let saturated = NSColor(
                    hue: hsb.hueComponent,
                    saturation: min(hsb.saturationComponent * 1.6, 1.0),
                    brightness: min(hsb.brightnessComponent * 0.85, 0.85),
                    alpha: 1.0
                )
                appIconColor = Color(nsColor: saturated)
            }
        }
        .onChange(of: appState.pinboardStore.pinboards) { lookupBoardColor() }
        .onChange(of: appState.pinboardStore.itemAssignmentVersion) { lookupBoardColor() }
    }

    // MARK: - Board Color

    private func lookupBoardColor() {
        guard boardColor == nil else { return }
        if let boardIds = try? appState.pinboardStore.pinboardsContaining(clipId: item.id),
           let firstBoardId = boardIds.first,
           let board = appState.pinboardStore.pinboards.first(where: { $0.id == firstBoardId }),
           let hex = board.color,
           let nsColor = ColorExtractor.parseHexColor(hex)
        {
            itemBoardColor = Color(nsColor: nsColor)
        } else {
            itemBoardColor = nil
        }
    }

    private var effectiveBoardColor: Color? {
        boardColor ?? itemBoardColor
    }

    private var cardBackgroundColor: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var headerColor: Color {
        effectiveBoardColor ?? appIconColor ?? Color(nsColor: .darkGray)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 8) {
            // Type name + time
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayTitle)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(relativeTime)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
            }

            // App icon — larger than header, clipped at bottom, pushed into corner
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 78, height: 78)
                    .offset(x: 24)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var cardContent: some View {
        switch item.contentType {
        case .text, .richText:
            TextCardContent(text: item.textContent ?? "")
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
        case .image:
            ImageCardContent(imagePath: item.imagePath, itemId: item.id)
        case .url:
            URLCardContent(text: item.textContent ?? "")
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        case .file:
            FileCardContent(paths: item.filePathsArray)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        case .color:
            ColorCardContent(text: item.textContent ?? "")
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
    }

    // MARK: - Footer

    private var footerText: String? {
        switch item.contentType {
        case .text, .richText:
            guard let text = item.textContent else { return nil }
            return L10n("card.characters", text.count)
        case .image:
            return nil
        case .url:
            return item.textContent
        case .file:
            let count = item.filePathsArray.count
            return count == 1 ? L10n("card.file.one") : L10n("card.files", count)
        case .color:
            return item.textContent
        }
    }

    // MARK: - Helpers

    private var relativeTime: String {
        let interval = -item.createdAt.timeIntervalSinceNow
        if interval < 60 { return L10n("card.time.now") }
        else if interval < 3600 { return L10n("card.time.minutes", Int(interval / 60)) }
        else if interval < 86400 { return L10n("card.time.hours", Int(interval / 3600)) }
        else { return L10n("card.time.days", Int(interval / 86400)) }
    }

    private func boardLabelColor(_ board: Pinboard) -> Color {
        if let hex = board.color, let nsColor = ColorExtractor.parseHexColor(hex) {
            return Color(nsColor: nsColor)
        }
        return .accentColor
    }

    private var appIcon: NSImage? {
        guard let bundleId = item.sourceAppId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var dragPayload: String {
        switch item.contentType {
        case .text, .richText, .url, .color:
            return item.textContent ?? ""
        case .image:
            return item.imagePath ?? ""
        case .file:
            return item.filePathsArray.first ?? ""
        }
    }
}
