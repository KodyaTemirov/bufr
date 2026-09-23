import SwiftUI

struct TextCardContent: View {
    let text: String

    var body: some View {
        let isCode = CardText.isCode(text)
        Text(String(text.prefix(800)))
            .font(isCode ? .system(size: 11.5, design: .monospaced) : .system(size: 13))
            .lineSpacing(isCode ? 1 : 2)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Long text fades out instead of stopping at a hard line
            .mask(LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.72), .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom
            ))
    }
}
