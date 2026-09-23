import CoreGraphics
import Testing
@testable import Bufr

@MainActor
final class FakeFrameSource: ScrollFrameSource {
    private(set) var onFrame: (@MainActor (CGImage) -> Void)?
    private(set) var onFailure: (@MainActor (Error) -> Void)?
    private(set) var stopped = false
    private(set) var events: [String] = []
    var startDelay: Duration = .zero

    func start(onFrame: @escaping @MainActor (CGImage) -> Void, onFailure: @escaping @MainActor (Error) -> Void) async throws {
        events.append("start")
        if startDelay > .zero {
            try? await Task.sleep(for: startDelay)
        }
        self.onFrame = onFrame
        self.onFailure = onFailure
        events.append("started")
    }

    func stop() async {
        events.append("stop")
        stopped = true
    }

    func send(_ image: CGImage) {
        onFrame?(image)
    }
}

/// Scrolls a synthetic page; like ScreenCaptureKit, sends no frame when nothing moved.
@MainActor
final class FakeScroller: AutoScrolling {
    var isAvailable = true
    /// Call number that scrolls `overshoot` times further than asked (app acceleration)
    var overshootCall: Int?
    var overshoot = 3
    private(set) var calls = 0
    private(set) var offset = 0
    private let page: CGImage
    private let frameHeight: Int
    private let source: FakeFrameSource

    init(page: CGImage, frameHeight: Int, source: FakeFrameSource) {
        self.page = page
        self.frameHeight = frameHeight
        self.source = source
    }

    func scroll(by points: CGFloat, at point: CGPoint) {
        calls += 1
        let distance = calls == overshootCall ? Int(points) * overshoot : Int(points)
        let next = max(0, min(page.height - frameHeight, offset + distance))
        guard next != offset else { return }
        offset = next
        source.send(ScrollPages.frame(of: page, offset: offset, height: frameHeight))
    }
}

@MainActor
struct ScrollingCaptureSessionTests {
    let region = ScrollRegion(
        displayID: 0, localRect: CGRect(x: 0, y: 0, width: 240, height: 400),
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), pointScale: 1,
        sourceAppId: nil, sourceAppName: nil
    )

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeSession(page: CGImage, pointerInRegion: @escaping @MainActor () -> Bool = { true }) -> (ScrollingCaptureSession, FakeFrameSource, FakeScroller) {
        let source = FakeFrameSource()
        let scroller = FakeScroller(page: page, frameHeight: 400, source: source)
        let session = ScrollingCaptureSession(
            region: region, source: source, scroller: scroller,
            stillFrameTimeout: .milliseconds(60), maxSettleWait: .milliseconds(300),
            showsPanels: false, pointerInRegion: pointerInRegion
        )
        return (session, source, scroller)
    }

    @Test func manualFramesAreStitchedAndFinishReturnsTheImage() async throws {
        let page = ScrollPages.page(height: 1600, seed: 11)
        let (session, source, _) = makeSession(page: page)
        let run = Task { await session.run() }
        try await waitUntil { source.onFrame != nil }

        for offset in [0, 100, 200, 300] {
            source.send(ScrollPages.frame(of: page, offset: offset, height: 400))
            try await waitUntil { Int(session.model.pixelSize.height) == offset + 400 }
        }
        session.finish()
        let image = try #require(await run.value)

        #expect(image.height == 700)
        #expect(source.stopped)
    }

    @Test func cancelReturnsNothing() async throws {
        let page = ScrollPages.page(height: 1600, seed: 12)
        let (session, source, _) = makeSession(page: page)
        let run = Task { await session.run() }
        try await waitUntil { source.onFrame != nil }
        source.send(ScrollPages.frame(of: page, offset: 0, height: 400))

        session.cancel()

        #expect(await run.value == nil)
        #expect(source.stopped)
    }

    @Test func autoScrollsToTheEndAndStops() async throws {
        let page = ScrollPages.page(height: 1600, seed: 13)
        let (session, source, scroller) = makeSession(page: page)
        let run = Task { await session.run() }
        try await waitUntil { source.onFrame != nil }
        source.send(ScrollPages.frame(of: page, offset: 0, height: 400))
        try await waitUntil { session.model.pixelSize.height == 400 }

        session.toggleAuto()
        try await waitUntil { !session.model.isAuto }

        #expect(session.model.hint == .end)
        #expect(scroller.offset == 1200)
        session.finish()
        let image = try #require(await run.value)
        #expect(ScrollPages.sameRGBA(image, page))
    }

    /// Review Focus 2: at the end of a page ScreenCaptureKit sends nothing at all.
    @Test func autoStopsAtTheEndWhenNoFramesArrive() async throws {
        let page = ScrollPages.page(height: 400, seed: 14) // already at the end
        let (session, source, scroller) = makeSession(page: page)
        let run = Task { await session.run() }
        try await waitUntil { source.onFrame != nil }
        source.send(ScrollPages.frame(of: page, offset: 0, height: 400))
        try await waitUntil { session.model.pixelSize.height == 400 }

        session.toggleAuto()
        try await waitUntil { !session.model.isAuto }

        #expect(session.model.hint == .end)
        #expect(scroller.calls == 3)
        session.cancel()
        _ = await run.value
    }

    @Test func autoWithoutAccessibilityExplainsAndStaysManual() async throws {
        let page = ScrollPages.page(height: 1600, seed: 15)
        let (session, source, scroller) = makeSession(page: page)
        scroller.isAvailable = false
        let run = Task { await session.run() }
        try await waitUntil { source.onFrame != nil }

        session.toggleAuto()

        #expect(session.model.autoUnavailable)
        #expect(!session.model.isAuto)
        #expect(scroller.calls == 0)
        session.cancel()
        _ = await run.value
    }

    /// Review #1: the app scrolled much further than asked; Auto scrolls back and goes on
    /// with smaller steps instead of losing the rest of the page.
    @Test func autoRecoversFromAnOvershoot() async throws {
        let page = ScrollPages.page(height: 1600, seed: 16)
        let (session, source, scroller) = makeSession(page: page)
        scroller.overshootCall = 2
        let run = Task { await session.run() }
        try await waitUntil { source.onFrame != nil }
        source.send(ScrollPages.frame(of: page, offset: 0, height: 400))
        try await waitUntil { session.model.pixelSize.height == 400 }

        session.toggleAuto()
        for _ in 0..<600 where session.model.isAuto {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(session.model.hint == .end)
        session.finish()
        let image = try #require(await run.value)
        #expect(ScrollPages.sameRGBA(image, page))
    }

    /// Review #4: an animation in the region keeps frames coming; Auto still moves on.
    @Test func autoDoesNotStallOnAnimation() async throws {
        let page = ScrollPages.textPage(width: 240, height: 400, seed: 17) // nothing to scroll
        let box = CGRect(x: 20, y: 150, width: 200, height: 40)
        let (session, source, _) = makeSession(page: page)
        let run = Task { await session.run() }
        try await waitUntil { source.onFrame != nil }
        source.send(ScrollPages.frame(of: page, offset: 0, height: 400, overlays: [.animatedBox(pageRect: box)]))
        try await waitUntil { session.model.pixelSize.height == 400 }
        let animation = Task { @MainActor in
            for index in 1..<400 where !Task.isCancelled {
                source.send(ScrollPages.frame(of: page, offset: 0, height: 400, overlays: [.animatedBox(pageRect: box)], frameIndex: index))
                try? await Task.sleep(for: .milliseconds(20))
            }
        }

        session.toggleAuto()
        for _ in 0..<500 where session.model.isAuto {
            try await Task.sleep(for: .milliseconds(10))
        }
        animation.cancel()

        #expect(!session.model.isAuto)
        #expect(session.model.hint == .end)
        session.cancel()
        _ = await run.value
    }

    /// Review #5: scroll events go to whatever is under the pointer.
    @Test func autoPausesWhenThePointerLeaves() async throws {
        let page = ScrollPages.page(height: 1600, seed: 18)
        var inside = true
        let (session, source, scroller) = makeSession(page: page, pointerInRegion: { inside })
        let run = Task { await session.run() }
        try await waitUntil { source.onFrame != nil }
        source.send(ScrollPages.frame(of: page, offset: 0, height: 400))
        try await waitUntil { session.model.pixelSize.height == 400 }

        session.toggleAuto()
        try await waitUntil { scroller.calls == 1 }
        inside = false
        try await waitUntil { !session.model.isAuto }

        #expect(session.model.hint == .pointerLeft)
        #expect(scroller.calls == 1)
        session.cancel()
        _ = await run.value
    }

    /// Review #10: Esc while the stream is still starting must not leave it running.
    @Test func sourceIsStoppedOnlyAfterItStarted() async throws {
        let page = ScrollPages.page(height: 1600, seed: 19)
        let (session, source, _) = makeSession(page: page)
        source.startDelay = .milliseconds(150)
        let run = Task { await session.run() }
        try await waitUntil { source.events.contains("start") }

        session.cancel()
        _ = await run.value

        #expect(source.events == ["start", "started", "stop"])
    }
}
