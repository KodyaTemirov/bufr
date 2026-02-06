import AppKit
import SwiftUI

struct FileCardContent: View {
    let paths: [String]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(paths.prefix(4), id: \.self) { path in
                VStack(spacing: 3) {
                    fileIcon(for: path)
                        .resizable()
                        .frame(width: 40, height: 40)
                    Text((path as NSString).lastPathComponent)
                        .font(.system(.caption, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
            }

            if paths.count > 4 {
                Text("+ \(paths.count - 4)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileIcon(for path: String) -> Image {
        let nsImage = NSWorkspace.shared.icon(forFile: path)
        return Image(nsImage: nsImage)
    }
}
