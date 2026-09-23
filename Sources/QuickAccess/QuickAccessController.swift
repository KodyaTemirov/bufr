import AppKit
import Observation

struct QuickAccessEntry: Identifiable {
    var id: UUID { item.id }
    var item: ClipItem
    let thumbnail: NSImage?
    /// Cocoa global rect of the captured content; "Pin" opens the pin right there
    let sourceRect: CGRect?
}

/// The stack of recent captures shown in a screen corner. Newest first; cards close
/// themselves after a delay. While the pointer is over any card the whole stack waits, so
/// cards never shift under the pointer.
@MainActor @Observable
final class QuickAccessController {
    static let maxVisible = 5

    private(set) var entries: [QuickAccessEntry] = []

    var visibleEntries: [QuickAccessEntry] { Array(entries.prefix(Self.maxVisible)) }
    var overflowCount: Int { max(0, entries.count - Self.maxVisible) }

    /// Called after every change (the panel resizes, shows or hides)
    @ObservationIgnored var onChange: () -> Void = {}

    @ObservationIgnored private let autoCloseDelay: () -> Duration?
    @ObservationIgnored private var timers: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var hovered: Set<UUID> = []

    /// `autoCloseDelay` returns nil for "never close automatically".
    init(autoCloseDelay: @escaping () -> Duration?) {
        self.autoCloseDelay = autoCloseDelay
    }

    func add(_ entry: QuickAccessEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        if hovered.isEmpty {
            scheduleAutoClose(entry.id)
        }
        onChange()
    }

    /// Closing a card never deletes anything: the item stays in history.
    func dismiss(_ id: UUID) {
        timers[id]?.cancel()
        timers[id] = nil
        let wasHovered = hovered.remove(id) != nil
        entries.removeAll { $0.id == id }
        // A card closed from its own buttons never reports the pointer leaving it
        if wasHovered, hovered.isEmpty {
            entries.forEach { scheduleAutoClose($0.id) }
        }
        onChange()
    }

    func dismissAll() {
        timers.values.forEach { $0.cancel() }
        timers = [:]
        hovered = []
        entries = []
        onChange()
    }

    func setHovered(_ id: UUID, _ isHovered: Bool) {
        if isHovered {
            hovered.insert(id)
            timers.values.forEach { $0.cancel() }
            timers = [:]
        } else {
            hovered.remove(id)
            guard hovered.isEmpty else { return }
            entries.forEach { scheduleAutoClose($0.id) }
        }
    }

    /// Shows a newer version of an item (e.g. after editing or saving elsewhere).
    func update(_ item: ClipItem) {
        guard let index = entries.firstIndex(where: { $0.id == item.id }) else { return }
        entries[index].item = item
    }

    private func scheduleAutoClose(_ id: UUID) {
        timers[id]?.cancel()
        timers[id] = nil
        guard hovered.isEmpty, entries.contains(where: { $0.id == id }), let delay = autoCloseDelay() else { return }
        timers[id] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }
}
