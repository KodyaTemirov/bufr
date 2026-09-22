import AppKit
import Testing
@testable import Bufr

@MainActor
struct QuickAccessQueueTests {
    let controller = QuickAccessController(autoCloseDelay: { nil })

    private func entry(_ n: Int) -> QuickAccessEntry {
        QuickAccessEntry(item: ClipItem(contentType: .image, hash: "h\(n)", origin: .screenshot), thumbnail: nil, sourceRect: nil)
    }

    @Test func newestComesFirst() {
        let first = entry(1), second = entry(2)
        controller.add(first)
        controller.add(second)

        #expect(controller.entries.map(\.id) == [second.id, first.id])
    }

    @Test func atMostFiveVisibleWithOverflowCount() {
        let all = (1...7).map(entry)
        all.forEach(controller.add)

        #expect(controller.visibleEntries.count == 5)
        #expect(controller.overflowCount == 2)
        #expect(controller.visibleEntries.first?.id == all.last?.id)
    }

    @Test func dismissingTopRevealsNext() {
        let all = (1...6).map(entry)
        all.forEach(controller.add)

        controller.dismiss(all[5].id)

        #expect(controller.visibleEntries.map(\.id) == all[0...4].reversed().map(\.id))
        #expect(controller.overflowCount == 0)
    }

    @Test func addingSameItemAgainMovesItToTop() {
        let first = entry(1), second = entry(2)
        controller.add(first)
        controller.add(second)
        controller.add(first)

        #expect(controller.entries.map(\.id) == [first.id, second.id])
    }
}

@MainActor
struct QuickAccessAutoCloseTests {
    private func entry() -> QuickAccessEntry {
        QuickAccessEntry(item: ClipItem(contentType: .image, hash: UUID().uuidString, origin: .screenshot), thumbnail: nil, sourceRect: nil)
    }

    @Test func closesAfterDelay() async throws {
        let controller = QuickAccessController(autoCloseDelay: { .milliseconds(100) })
        controller.add(entry())

        try await Task.sleep(for: .milliseconds(400))

        #expect(controller.entries.isEmpty)
    }

    @Test func hoverPausesAndLeavingRestartsTheTimer() async throws {
        let controller = QuickAccessController(autoCloseDelay: { .milliseconds(100) })
        let card = entry()
        controller.add(card)
        controller.setHovered(card.id, true)

        try await Task.sleep(for: .milliseconds(400))
        #expect(controller.entries.count == 1)

        controller.setHovered(card.id, false)
        try await Task.sleep(for: .milliseconds(400))
        #expect(controller.entries.isEmpty)
    }

    @Test func neverClosesWhenDisabled() async throws {
        let controller = QuickAccessController(autoCloseDelay: { nil })
        controller.add(entry())

        try await Task.sleep(for: .milliseconds(200))

        #expect(controller.entries.count == 1)
    }
}
