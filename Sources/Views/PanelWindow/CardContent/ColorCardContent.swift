import SwiftUI

/// A large sample with its HEX and RGB values.
struct ColorCardContent: View {
    let text: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ColorExtractor.parseHexColor(text).map { Color(nsColor: $0) } ?? Color.gray.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(text.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                if let rgb = ColorExtractor.rgbDescription(text) {
                    Text(rgb)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: .rect(cornerRadius: 6, style: .continuous))
            .padding(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
