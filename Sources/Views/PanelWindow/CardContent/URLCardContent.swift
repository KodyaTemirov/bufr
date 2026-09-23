import SwiftUI

/// The site big, the rest of the link small.
struct URLCardContent: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.gradient, in: .rect(cornerRadius: 8, style: .continuous))

            if let parts = URLParts(string: text) {
                Text(parts.host)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                if !parts.path.isEmpty {
                    Text(parts.path)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                }
            } else {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
