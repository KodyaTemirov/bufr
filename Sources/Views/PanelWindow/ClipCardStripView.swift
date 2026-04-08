import SwiftUI

struct ClipCardStripView: View {
    let items: [ClipItem]
    @Binding var selectedIndex: Int
    var boardColor: Color? = nil
    var axis: Axis = .horizontal
    let onPaste: (ClipItem) -> Void
    var onRename: ((ClipItem) -> Void)? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(axis == .horizontal ? .horizontal : .vertical, showsIndicators: false) {
                let layout = axis == .horizontal
                    ? AnyLayout(HStackLayout(spacing: 10))
                    : AnyLayout(VStackLayout(spacing: 10))

                layout {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipCardView(
                            item: item,
                            isSelected: index == selectedIndex,
                            boardColor: boardColor,
                            shortcutIndex: index < 9 ? index + 1 : nil,
                            onRename: onRename
                        )
                        .cardWidth(axis: axis)
                        .id(item.id)
                        .onTapGesture {
                            selectedIndex = index
                            onPaste(item)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, axis == .horizontal ? 16 : 8)
                .padding(.top, axis == .horizontal ? 8 : 0)
                .padding(.bottom, axis == .horizontal ? 8 : 12)
            }
            .scrollTargetBehavior(.viewAligned)
            .onChange(of: selectedIndex) { _, newValue in
                guard let item = items[safe: newValue] else { return }
                withAnimation(.spring(duration: 0.25)) {
                    proxy.scrollTo(item.id, anchor: .center)
                }
            }
        }
        .frame(
            maxWidth: axis == .horizontal ? .infinity : nil,
            maxHeight: axis == .horizontal ? 220 : .infinity
        )
    }
}


// MARK: - Card width modifier

private struct CardWidthModifier: ViewModifier {
    let axis: Axis

    func body(content: Content) -> some View {
        if axis == .horizontal {
            content.frame(width: 240)
        } else {
            content.frame(maxWidth: .infinity)
        }
    }
}

extension View {
    func cardWidth(axis: Axis) -> some View {
        modifier(CardWidthModifier(axis: axis))
    }
}

// MARK: - Safe array subscript

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
