import SwiftUI

struct ImageCardContent: View {
    let imagePath: String?
    let itemId: UUID

    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.quaternary)
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
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
        }
    }
}
