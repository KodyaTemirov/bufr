import AppKit
import SwiftUI

struct ClipCardStripView: View {
    let items: [ClipItem]
    @Binding var selectedIndex: Int
    var boardColor: Color? = nil
    let onPaste: (ClipItem) -> Void
    var onRename: ((ClipItem) -> Void)? = nil

    var body: some View {
        ScrollViewReader { proxy in
            HorizontalMouseScrollView {
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
                .scrollTargetLayout()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
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

// MARK: - Horizontal scroll view with mouse wheel support

/// Wraps an NSScrollView that supports horizontal scrolling via vertical mouse wheel.
private struct HorizontalMouseScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> HorizontalNSScrollView {
        let scrollView = HorizontalNSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.drawsBackground = false

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hostingView

        // Pin hosting view height to scroll view
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
        ])

        return scrollView
    }

    func updateNSView(_ nsView: HorizontalNSScrollView, context: Context) {
        if let hostingView = nsView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
        }
    }
}

private final class HorizontalNSScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        // If already scrolling horizontally (trackpad), pass through normally
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            super.scrollWheel(with: event)
            return
        }

        // Convert vertical scroll to horizontal
        if abs(event.scrollingDeltaY) > 0 {
            let clipView = contentView
            var origin = clipView.bounds.origin
            origin.x -= event.scrollingDeltaY * 3
            let maxX = max(0, (documentView?.frame.width ?? 0) - clipView.bounds.width)
            origin.x = min(max(0, origin.x), maxX)
            clipView.scroll(to: origin)
            reflectScrolledClipView(clipView)
        }
    }
}

// MARK: - Safe array subscript

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
