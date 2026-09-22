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
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: QuickAccessPresenter.overflowHeight)
                    .background(.black.opacity(0.7), in: .capsule)
            }
            ForEach(controller.visibleEntries.reversed()) { entry in
                QuickAccessCardView(entry: entry, controller: controller, actions: actions)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(QuickAccessPresenter.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(duration: 0.3), value: controller.visibleEntries.map(\.id))
    }
}
