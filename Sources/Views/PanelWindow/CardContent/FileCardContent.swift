import SwiftUI

struct FileCardContent: View {
    let paths: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(paths.prefix(4), id: \.self) { path in
                HStack(spacing: 5) {
                    Image(systemName: "doc.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text((path as NSString).lastPathComponent)
                        .font(.system(.caption, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if paths.count > 4 {
                Text("+ \(paths.count - 4)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
