import SwiftUI

struct ClipCardStripView: View {
    let items: [ClipItem]
    @Binding var selectedIndex: Int
    var boardColor: Color? = nil
    let onPaste: (ClipItem) -> Void
    var onRename: ((ClipItem) -> Void)? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipCardView(
                            item: item,
                            isSelected: index == selectedIndex,
                            boardColor: boardColor,
                            onRename: onRename
                        )
                        .id(item.id)
                        .onTapGesture {
                            selectedIndex = index
                            onPaste(item)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollTargetBehavior(.viewAligned)
            .onChange(of: selectedIndex) { _, newValue in
                guard let item = items[safe: newValue] else { return }
                withAnimation(.spring(duration: 0.25)) {
                    proxy.scrollTo(item.id, anchor: .center)
                }
            }
        }
        .frame(height: 220)
    }
}

// MARK: - Safe array subscript

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
