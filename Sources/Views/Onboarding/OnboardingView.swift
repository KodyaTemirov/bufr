import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    let onComplete: () -> Void

    @State private var currentPage = 0

    private var pages: [OnboardingPage] {
        [
            OnboardingPage(
                icon: "clipboard",
                title: L10n("onboarding.page1.title"),
                subtitle: L10n("onboarding.page1.subtitle"),
                description: L10n("onboarding.page1.description")
            ),
            OnboardingPage(
                icon: "command",
                title: L10n("onboarding.page2.title"),
                subtitle: L10n("onboarding.page2.subtitle"),
                description: L10n("onboarding.page2.description")
            ),
            OnboardingPage(
                icon: "magnifyingglass",
                title: L10n("onboarding.page3.title"),
                subtitle: L10n("onboarding.page3.subtitle"),
                description: L10n("onboarding.page3.description")
            ),
            OnboardingPage(
                icon: "rectangle.on.rectangle",
                title: L10n("onboarding.page4.title"),
                subtitle: L10n("onboarding.page4.subtitle"),
                description: L10n("onboarding.page4.description")
            ),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    pageView(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.automatic)
            .frame(height: 300)

            // Page indicator
            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.accentColor : Color.primary.opacity(0.2))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }
            .padding(.bottom, 16)

            // Navigation buttons
            HStack {
                if currentPage > 0 {
                    Button(L10n("onboarding.back")) {
                        withAnimation { currentPage -= 1 }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if currentPage < pages.count - 1 {
                    Button(L10n("onboarding.next")) {
                        withAnimation { currentPage += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(L10n("onboarding.start")) {
                        onComplete()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 420, height: 400)
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 16) {
            Image(systemName: page.icon)
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 24)

            Text(page.title)
                .font(.title2)
                .fontWeight(.bold)

            Text(page.subtitle)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(page.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

private struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let description: String
}
