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
    /// Timers run on the main actor, which a parallel test run can keep busy: wait for the
    /// outcome instead of a fixed time.
    private func waitUntilClosed(_ controller: QuickAccessController) async throws {
        for _ in 0..<300 where !controller.entries.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func entry() -> QuickAccessEntry {
        QuickAccessEntry(item: ClipItem(contentType: .image, hash: UUID().uuidString, origin: .screenshot), thumbnail: nil, sourceRect: nil)
    }

    @Test func closesAfterDelay() async throws {
        let controller = QuickAccessController(autoCloseDelay: { .milliseconds(100) })
        controller.add(entry())

        try await waitUntilClosed(controller)

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
        try await waitUntilClosed(controller)
        #expect(controller.entries.isEmpty)
    }

    @Test func neverClosesWhenDisabled() async throws {
        let controller = QuickAccessController(autoCloseDelay: { nil })
        controller.add(entry())

        try await Task.sleep(for: .milliseconds(200))

        #expect(controller.entries.count == 1)
    }

    /// Cards below or above the hovered one must not expire and shift the stack under the pointer.
    @Test func hoveringAnyCardPausesTheWholeStack() async throws {
        let controller = QuickAccessController(autoCloseDelay: { .milliseconds(100) })
        let older = entry(), newer = entry()
        controller.add(older)
        controller.add(newer)
        controller.setHovered(older.id, true)

        try await Task.sleep(for: .milliseconds(400))
        #expect(controller.entries.count == 2)

        controller.setHovered(older.id, false)
        try await waitUntilClosed(controller)
        #expect(controller.entries.isEmpty)
    }

    /// Copy, Annotate, Pin or × close the hovered card; the pointer never "leaves" it, so the
    /// rest of the stack must start closing on its own again.
    @Test func closingTheHoveredCardResumesTheOthers() async throws {
        let controller = QuickAccessController(autoCloseDelay: { .milliseconds(100) })
        let older = entry(), newer = entry()
        controller.add(older)
        controller.add(newer)
        controller.setHovered(newer.id, true)

        controller.dismiss(newer.id)
        try await waitUntilClosed(controller)

        #expect(controller.entries.isEmpty)
    }
}

struct QuickAccessThumbnailTests {
    /// A 5K capture must not stay alive behind a 220 pt card.
    @Test func thumbnailIsSmallAndIndependent() throws {
        let thumbnail = QuickAccessThumbnail.make(from: TestImages.cgImage(width: 5120, height: 2880), pointScale: 2)
        let cgImage = try #require(thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil))

        #expect(cgImage.width <= QuickAccessThumbnail.maxPixelSize)
        #expect(cgImage.height <= QuickAccessThumbnail.maxPixelSize)
        #expect(abs(thumbnail.size.width / thumbnail.size.height - 5120.0 / 2880.0) < 0.02)
    }
}
