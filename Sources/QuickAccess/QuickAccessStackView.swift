import SwiftUI

/// Newest card at the bottom (closest to the corner), older ones above, then "+N".
struct QuickAccessStackView: View {
    let controller: QuickAccessController
    let actions: QuickAccessActions

    var body: some View {
        VStack(spacing: QuickAccessPresenter.spacing) {
            Spacer(minLength: 0)
            if controller.overflowCount > 0 {
                Text("+\(controller.overflowCount)")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: QuickAccessPresenter.overflowHeight)
                    .glassEffect(.regular, in: .capsule)
            }
            ForEach(controller.visibleEntries.reversed()) { entry in
                QuickAccessCardView(entry: entry, controller: controller, actions: actions)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85, anchor: .bottom).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .padding(QuickAccessPresenter.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(duration: 0.35, bounce: 0.25), value: controller.visibleEntries.map(\.id))
    }
}
