import SwiftUI

struct TextCardContent: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.subheadline, design: .monospaced))
            .lineLimit(6)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
