import AppKit
import SwiftUI

/// One file: its icon and name. Several: a fan of icons and how many there are.
struct FileCardContent: View {
    let paths: [String]

    var body: some View {
        VStack(spacing: 8) {
            if paths.count == 1, let path = paths.first {
                icon(for: path)
                    .resizable()
                    .frame(width: 56, height: 56)
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.middle)
            } else {
                ZStack {
                    ForEach(Array(paths.prefix(3).enumerated()), id: \.offset) { index, path in
                        let position = CGFloat(index) - CGFloat(min(paths.count, 3) - 1) / 2
                        icon(for: path)
                            .resizable()
                            .frame(width: 46, height: 46)
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            .rotationEffect(.degrees(position * 10))
                            .offset(x: position * 20, y: abs(position) * 3)
                    }
                }
                .frame(height: 58)
                Text(L10n("card.files", paths.count))
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func icon(for path: String) -> Image {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
    }
}
