import SwiftUI

struct RetentionSlider: View {
    @Binding var selectedIndex: Int
    let labels: [String]

    @State private var isDragging = false

    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 20
    private let dotSize: CGFloat = 6

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let count = labels.count
                let usableWidth = geo.size.width - thumbSize
                let stepWidth = count > 1 ? usableWidth / CGFloat(count - 1) : 0

                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: trackHeight)
                        .padding(.horizontal, thumbSize / 2)

                    // Dots
                    ForEach(0..<count, id: \.self) { i in
                        Circle()
                            .fill(i == selectedIndex ? Color.accentColor : Color.primary.opacity(0.2))
                            .frame(width: dotSize, height: dotSize)
                            .offset(x: thumbSize / 2 - dotSize / 2 + stepWidth * CGFloat(i))
                    }

                    // Thumb
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        .shadow(color: .black.opacity(0.06), radius: 1, y: 0)
                        .frame(width: thumbSize, height: thumbSize)
                        .offset(x: stepWidth * CGFloat(selectedIndex))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDragging = true
                                    let x = value.location.x - thumbSize / 2
                                    let nearest = Int((x / stepWidth).rounded())
                                        .clamped(to: 0...(count - 1))
                                    if nearest != selectedIndex {
                                        selectedIndex = nearest
                                    }
                                }
                                .onEnded { _ in
                                    isDragging = false
                                }
                        )
                }
                .frame(height: thumbSize)
            }
            .frame(height: thumbSize)

            // Labels
            HStack {
                ForEach(labels.indices, id: \.self) { i in
                    Text(labels[i])
                        .font(.caption2)
                        .fontWeight(i == selectedIndex ? .semibold : .regular)
                        .foregroundStyle(i == selectedIndex ? .primary : .secondary)
                    if i < labels.count - 1 { Spacer() }
                }
            }
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
