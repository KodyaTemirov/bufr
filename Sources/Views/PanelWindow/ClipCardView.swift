import AppKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.bufr.app", category: "ClipCardView")

// MARK: - App Icon & Color Cache

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private var icons: [String: NSImage] = [:]
    private var colors: [String: Color] = [:]

    func icon(for bundleId: String) -> NSImage? {
        if let cached = icons[bundleId] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleId] = icon
        return icon
    }

    func dominantColor(for bundleId: String) -> Color? {
        if let cached = colors[bundleId] { return cached }
        guard let icon = icon(for: bundleId),
              let dominant = ColorExtractor.dominantColor(from: icon),
              let hsb = dominant.usingColorSpace(.deviceRGB)
        else { return nil }
        let saturated = NSColor(
            hue: hsb.hueComponent,
            saturation: min(hsb.saturationComponent * 1.6, 1.0),
            brightness: min(hsb.brightnessComponent * 0.85, 0.85),
            alpha: 1.0
        )
        let color = Color(nsColor: saturated)
        colors[bundleId] = color
        return color
    }
}

struct ClipCardView: View {
    @Environment(AppState.self) private var appState
    let item: ClipItem
    let isSelected: Bool
    var boardColor: Color? = nil
    var shortcutIndex: Int? = nil

    var onRename: ((ClipItem) -> Void)? = nil

    @State private var isHovered = false
    @State private var itemBoardColor: Color?


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
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .stroke(
                    (isSelected || isHovered)
                        ? (effectiveBoardColor?.opacity(0.7) ?? Color.accentColor.opacity(0.7))
                        : Color(nsColor: .separatorColor),
                    lineWidth: (isSelected || isHovered) ? 2 : 1
                )
        )
        .overlay(alignment: .bottomTrailing) {
            if let index = shortcutIndex {
                Text("⌘\(index)")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .controlBackgroundColor), in: .capsule)
                    .overlay(Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                    .padding(8)
            }
        }
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
        .task(id: item.id) {
            lookupBoardColor()
        }
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
        effectiveBoardColor ?? cachedAppIconColor ?? Color(nsColor: .darkGray)
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
            let paths = item.filePathsArray
            if paths.count == 1, let path = paths.first {
                let url = URL(fileURLWithPath: path)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? UInt64 {
                    return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                }
                return L10n("card.file.one")
            }
            return L10n("card.files", paths.count)
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
        guard let bundleId = item.sourceAppId else { return nil }
        return AppIconCache.shared.icon(for: bundleId)
    }

    private var cachedAppIconColor: Color? {
        guard let bundleId = item.sourceAppId else { return nil }
        return AppIconCache.shared.dominantColor(for: bundleId)
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
