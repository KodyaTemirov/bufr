import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    let onComplete: () -> Void

    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "clipboard",
            title: "Добро пожаловать в Bufr",
            subtitle: "Бесплатный менеджер буфера обмена для macOS",
            description: "Bufr автоматически сохраняет всё, что вы копируете — текст, изображения, файлы, ссылки и цвета."
        ),
        OnboardingPage(
            icon: "command",
            title: "Быстрый доступ",
            subtitle: "⌘⇧V — ваш горячий клавиш",
            description: "Нажмите ⌘⇧V в любом приложении, чтобы открыть панель Bufr. Используйте стрелки для навигации и Enter для вставки."
        ),
        OnboardingPage(
            icon: "magnifyingglass",
            title: "Мгновенный поиск",
            subtitle: "Находите нужное за секунды",
            description: "Начните вводить текст для поиска по истории. Используйте фильтры для сортировки по типу контента."
        ),
        OnboardingPage(
            icon: "rectangle.on.rectangle",
            title: "Доски",
            subtitle: "Организуйте важное",
            description: "Создавайте тематические доски и добавляйте элементы через контекстное меню (правый клик на карточке)."
        ),
    ]

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
                    Button("Назад") {
                        withAnimation { currentPage -= 1 }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if currentPage < pages.count - 1 {
                    Button("Далее") {
                        withAnimation { currentPage += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Начать работу") {
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
