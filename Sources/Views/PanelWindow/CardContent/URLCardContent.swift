import SwiftUI

struct URLCardContent: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "link")
                .font(.title3)
                .foregroundStyle(.blue)

            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .lineLimit(4)
                .foregroundStyle(.blue)
                .underline()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
