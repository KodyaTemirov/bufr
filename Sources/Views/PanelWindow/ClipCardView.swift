import AppKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.bufr.app", category: "ClipCardView")

struct ClipCardView: View {
    @Environment(AppState.self) private var appState
    let item: ClipItem
    let isSelected: Bool
    var boardColor: Color? = nil

    @State private var isHovered = false
    @State private var itemBoardColor: Color?
    @State private var appIconColor: Color?

    private let cardRadius: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            // Compact header: icon + meta on left, app icon on right
            headerRow
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(headerColor?.opacity(0.4) ?? .clear)

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
                Menu("Добавить на доску") {
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

            Button("Копировать") {
                appState.clipboardPaster.copyToClipboard(item)
            }

            Divider()

            Button("Удалить", role: .destructive) {
                appState.deleteItem(item)
            }
        }
        .task {
            lookupBoardColor()
            if let icon = appIcon,
               let dominant = ColorExtractor.dominantColor(from: icon) {
                appIconColor = Color(nsColor: dominant)
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

    private var headerColor: Color? {
        effectiveBoardColor ?? appIconColor
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 8) {
            // Type name + time
            VStack(alignment: .leading, spacing: 1) {
                Text(item.contentType.displayName)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(relativeTime)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
            }

            // App icon
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .frame(width: 40, height: 40)
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
            return "\(text.count) символов"
        case .image:
            return nil
        case .url:
            return item.textContent
        case .file:
            let count = item.filePathsArray.count
            return count == 1 ? "1 файл" : "\(count) файлов"
        case .color:
            return item.textContent
        }
    }

    // MARK: - Helpers

    private var relativeTime: String {
        let interval = -item.createdAt.timeIntervalSinceNow
        if interval < 60 { return "только что" }
        else if interval < 3600 { return "\(Int(interval / 60)) мин назад" }
        else if interval < 86400 { return "\(Int(interval / 3600)) ч назад" }
        else { return "\(Int(interval / 86400)) д назад" }
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
