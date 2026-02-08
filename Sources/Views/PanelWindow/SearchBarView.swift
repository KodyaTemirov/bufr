import SwiftUI

struct SearchBarView: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(.body, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField(L10n("search.placeholder"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .rounded))
                .focused($isFocused)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
        .onAppear {
            isFocused = true
        }
    }
}
