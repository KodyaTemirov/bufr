import SwiftUI

struct ImageCardContent: View {
    let imagePath: String?
    let itemId: UUID

    @State private var thumbnail: NSImage?
    @State private var hasTransparency = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let thumbnail {
                    // The empty sides show a blurred copy of the picture, like a photo on its colours
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 20)
                        .opacity(0.55)
                        .clipped()

                    let fitted = Self.fittedSize(thumbnail.size, in: proxy.size)
                    ZStack {
                        if hasTransparency {
                            Checkerboard()
                        }
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                    }
                    .frame(width: fitted.width, height: fitted.height)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.quaternary)
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .task {
            // imagePath is like "UUID.png" — extract UUID from filename
            if let imagePath,
               let imageUUID = UUID(uuidString: String(imagePath.dropLast(4)))
            {
                thumbnail = await ImageStorage.shared.loadThumbnail(id: imageUUID)
            }
            // Fallback: try item ID directly
            if thumbnail == nil {
                thumbnail = await ImageStorage.shared.loadThumbnail(id: itemId)
            }
            // Last resort: load full image
            if thumbnail == nil, let imagePath {
                thumbnail = await ImageStorage.shared.loadImage(filename: imagePath)
            }
            if let thumbnail {
                hasTransparency = Self.hasTransparency(thumbnail)
            }
        }
    }
}

extension ImageCardContent {
    /// The picture's size when fitted into `container`.
    static func fittedSize(_ image: CGSize, in container: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return container }
        let scale = min(container.width / image.width, container.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    /// Whether any pixel is see-through (checked on a small copy).
    static func hasTransparency(_ image: NSImage) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cgImage.alphaInfo != .none, cgImage.alphaInfo != .noneSkipFirst, cgImage.alphaInfo != .noneSkipLast
        else { return false }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 250 }
    }
}

/// Grey squares behind see-through pictures.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let square: CGFloat = 6
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.92)))
            for row in 0..<Int(size.height / square) + 1 {
                for column in 0..<Int(size.width / square) + 1 where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square)
                    context.fill(Path(rect), with: .color(Color(white: 0.8)))
                }
            }
        }
    }
}
