import SwiftUI

struct ClipPanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @State private var selectedIndex: Int = 0
    @State private var searchQuery: String = ""
    @State private var searchResults: [ClipItem]?
    @State private var selectedBoardId: UUID?
    @State private var showQuickPreview = false
    @State private var showCreateSheet = false
    @State private var showKeyHints = false
    @State private var boardToDelete: Pinboard?
    @State private var boardToEdit: Pinboard?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header: search + board tabs + actions
                headerBar
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                // Content: cards
                cardContent
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
            .onKeyPress(.space) {
                guard !displayedItems.isEmpty else { return .ignored }
                withAnimation(.easeInOut(duration: 0.2)) {
                    showQuickPreview.toggle()
                }
                return .handled
            }
            .onKeyPress(.leftArrow) {
                moveSelection(by: -1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                moveSelection(by: 1)
                return .handled
            }
            .onKeyPress(phases: .down) { keyPress in
                if keyPress.key == .return && keyPress.modifiers.contains(.option) {
                    pasteSelected(plainText: true)
                    return .handled
                }
                if keyPress.key == .return {
                    pasteSelected(plainText: false)
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.escape) {
                if showQuickPreview {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showQuickPreview = false
                    }
                    return .handled
                }
                appState.hidePanel()
                return .handled
            }

            // Quick Look overlay
            if showQuickPreview, let item = displayedItems[safe: selectedIndex] {
                QuickPreviewView(item: item) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showQuickPreview = false
                    }
                }
            }
        }
        .onChange(of: searchQuery) {
            performSearch()
            selectedIndex = 0
        }
        .onChange(of: appState.clipItemStore.items) {
            performSearch()
            selectedIndex = 0
        }
        .sheet(isPresented: $showCreateSheet) {
            CreatePinboardSheet(
                usedColors: Set(appState.pinboardStore.pinboards.compactMap(\.color))
            ) { name, icon, color in
                _ = try? appState.pinboardStore.create(name: name, icon: icon, color: color)
            }
        }
        .sheet(isPresented: .init(
            get: { boardToEdit != nil },
            set: { if !$0 { boardToEdit = nil } }
        )) {
            if let board = boardToEdit {
                EditPinboardSheet(
                    pinboard: board,
                    usedColors: Set(appState.pinboardStore.pinboards.compactMap(\.color))
                ) { newName, newColor in
                    var updated = board
                    updated.name = newName
                    updated.color = newColor
                    try? appState.pinboardStore.update(updated)
                }
            }
        }
        .confirmationDialog(
            "Удалить доску «\(boardToDelete?.name ?? "")»?",
            isPresented: .init(
                get: { boardToDelete != nil },
                set: { if !$0 { boardToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let board = boardToDelete {
                    try? appState.pinboardStore.delete(board)
                    if selectedBoardId == board.id {
                        selectedBoardId = nil
                    }
                }
                boardToDelete = nil
            }
        }
        .task {
            try? appState.pinboardStore.fetchPinboards()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Search
            SearchBarView(query: $searchQuery)
                .frame(maxWidth: 240)

            // Divider
            RoundedRectangle(cornerRadius: 0.5)
                .fill(.quaternary)
                .frame(width: 1, height: 22)
                .padding(.horizontal, 4)

            // Board tabs (scrollable)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    // Clipboard history tab (always first)
                    BoardTabButton(
                        label: "Буфер обмена",
                        systemImage: "clipboard",
                        isSelected: selectedBoardId == nil,
                        action: { selectClipboard() }
                    )

                    // Pinboard tabs
                    ForEach(appState.pinboardStore.pinboards) { board in
                        BoardTabButton(
                            label: board.name,
                            isSelected: selectedBoardId == board.id,
                            color: boardColor(board),
                            action: { selectBoard(board.id) }
                        )
                        .contextMenu {
                            Button("Редактировать") {
                                boardToEdit = board
                            }
                            Divider()
                            Button("Удалить", role: .destructive) {
                                boardToDelete = board
                            }
                        }
                    }
                }
            }

            // Add board button
            Button {
                showCreateSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)

            // Settings button
            Button {
                appState.hidePanel()
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)

            // Keyboard hints button
            Button {
                showKeyHints.toggle()
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(showKeyHints ? .primary : .secondary)
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showKeyHints, arrowEdge: .bottom) {
                footerBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }

            // Close button
            Button {
                appState.hidePanel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Card Content

    private var cardContent: some View {
        Group {
            if displayedItems.isEmpty {
                emptyState
            } else {
                ClipCardStripView(
                    items: displayedItems,
                    selectedIndex: $selectedIndex,
                    boardColor: selectedBoardColor,
                    onPaste: { item in
                        appState.pasteItem(item)
                    }
                )
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            keyHint("←→", label: "навигация")
            keyHint("⏎", label: "вставить")
            keyHint("⌥⏎", label: "plain text")
            keyHint("⎵", label: "превью")
            keyHint("⎋", label: "закрыть")
        }
    }

    // MARK: - Computed

    private var displayedItems: [ClipItem] {
        if selectedBoardId != nil {
            return appState.pinboardStore.currentBoardItems
        }

        return searchResults ?? appState.clipItemStore.items
    }

    // MARK: - Search

    private func performSearch() {
        guard selectedBoardId == nil else { return }
        if searchQuery.isEmpty {
            searchResults = nil
        } else {
            searchResults = try? appState.clipItemStore.search(query: searchQuery)
        }
    }

    // MARK: - Board Selection

    private func selectClipboard() {
        selectedBoardId = nil
        selectedIndex = 0
    }

    private func selectBoard(_ id: UUID) {
        selectedBoardId = id
        selectedIndex = 0
        try? appState.pinboardStore.fetchClips(for: id)
    }

    private func boardColor(_ board: Pinboard) -> Color? {
        guard let hex = board.color,
              let nsColor = ColorExtractor.parseHexColor(hex)
        else { return nil }
        return Color(nsColor: nsColor)
    }

    private var selectedBoardColor: Color? {
        guard let boardId = selectedBoardId,
              let board = appState.pinboardStore.pinboards.first(where: { $0.id == boardId })
        else { return nil }
        return boardColor(board)
    }

    // MARK: - Actions

    private func moveSelection(by offset: Int) {
        let newIndex = selectedIndex + offset
        guard newIndex >= 0, newIndex < displayedItems.count else { return }
        selectedIndex = newIndex
    }

    private func pasteSelected(plainText: Bool) {
        guard let item = displayedItems[safe: selectedIndex] else { return }
        appState.pasteItem(item, asPlainText: plainText)
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedBoardId != nil ? "tray" : (searchQuery.isEmpty ? "clipboard" : "magnifyingglass"))
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(selectedBoardId != nil ? "Доска пуста" : (searchQuery.isEmpty ? "История пуста" : "Ничего не найдено"))
                .font(.system(.title3, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
            Text(selectedBoardId != nil ? "Добавьте элементы через контекстное меню" : (searchQuery.isEmpty ? "Скопируйте что-нибудь для начала" : "Попробуйте изменить запрос"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }

    private func keyHint(_ key: String, label: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .frame(minWidth: 40)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: .capsule)
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Board Tab Button

private struct BoardTabButton: View {
    let label: String
    var systemImage: String? = nil
    let isSelected: Bool
    var color: Color? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(.subheadline, weight: .medium))
                } else if let color {
                    Circle()
                        .fill(color)
                        .frame(width: 12, height: 12)
                }
                Text(label)
                    .font(.system(.body, design: .rounded, weight: .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.black : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background {
                if isSelected {
                    Capsule().fill(Color.white.opacity(0.25))
                } else {
                    Capsule().fill(isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                }
            }
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
