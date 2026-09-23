import CoreGraphics
import Testing
@testable import Bufr

/// Screens that look like the real thing (text, tables, chats, sidebars, translucent headers,
/// animations) — much less distinctive than random blocks.
struct ScrollStitcherRealisticTests {
    private let frameHeight = 500

    private func run(_ page: CGImage, offsets: [Int], overlays: [ScrollPages.Overlay] = []) -> (ScrollStitcher, [ScrollStitcher.Step]) {
        let frames = offsets.enumerated().map { ScrollPages.frame(of: page, offset: $1, height: frameHeight, overlays: overlays, frameIndex: $0) }
        let stitcher = ScrollStitcher(firstFrame: frames[0])
        return (stitcher, frames.dropFirst().map { stitcher.append($0) })
    }

    /// Manual scrolling: uneven steps between 10 and 150 px.
    private func manualOffsets(to end: Int, seed: UInt64) -> [Int] {
        var rng = SeededGenerator(seed: seed)
        var offsets = [0]
        while offsets.last! < end {
            offsets.append(min(end, offsets.last! + Int.random(in: 10...150, using: &rng)))
        }
        return offsets
    }

    @Test func articleWithManualSteps() throws {
        let page = ScrollPages.textPage()
        let offsets = manualOffsets(to: 2400, seed: 1)
        let (stitcher, steps) = run(page, offsets: offsets)
        let result = try #require(stitcher.compose())

        #expect(!steps.contains(.lostTrack))
        #expect(result.height == 2900)
        #expect(ScrollPages.sameRows(result, page, 0..<2900))
    }

    /// Review #2: rows that differ in a few digits must not be matched a row off.
    @Test func uniformTableWithVaryingSteps() throws {
        let page = ScrollPages.tablePage(width: 1400) // 64 buckets of 22 px: rows nearly equal
        let offsets = [0, 37, 159, 220, 370, 458, 700, 761, 1000, 1122, 1300, 1450, 1731, 1900, 2150, 2400]
        let (stitcher, _) = run(page, offsets: offsets)
        let result = try #require(stitcher.compose())

        #expect(result.height == 2900)
        #expect(ScrollPages.sameRows(result, page, 0..<2900))
    }

    @Test func chatWithManualSteps() throws {
        let page = ScrollPages.chatPage()
        let (stitcher, steps) = run(page, offsets: manualOffsets(to: 2400, seed: 2))
        let result = try #require(stitcher.compose())

        #expect(!steps.contains(.lostTrack))
        #expect(ScrollPages.sameRows(result, page, 0..<2900))
    }

    /// Review #3: a window picked with Space has a sidebar that doesn't scroll.
    @Test func windowWithAStaticSidebar() throws {
        let page = ScrollPages.textPage(seed: 22)
        let offsets = Array(stride(from: 0, through: 2400, by: 120))
        let (stitcher, steps) = run(page, offsets: offsets, overlays: [.sidebar(width: 150)])
        let result = try #require(stitcher.compose())

        #expect(!steps.contains(.lostTrack))
        #expect(result.height == 2900)
        #expect(ScrollPages.sameRows(result, page, 0..<2900, columns: 150..<page.width))
    }

    /// Review #1b: when only blank rows overlap, the shift can't be known — the stitcher must
    /// not guess (a wrong guess cuts or repeats content); a smaller step then goes on exactly.
    /// "Auto" does that by itself (scrolls back and halves the step).
    @Test func blankGapIsNeverGuessedAcross() throws {
        let page = ScrollPages.textPage(seed: 23, gap: (start: 900, height: 350))
        let offsets = [0, 250, 500, 750, 1000, 875, 1000, 1125, 1250, 1500, 1750, 2000, 2250, 2500]
        let (stitcher, steps) = run(page, offsets: offsets)
        let result = try #require(stitcher.compose())

        #expect(steps[3] == .lostTrack) // 750 → 1000: nothing but blank overlaps
        #expect(steps.filter { $0 == .lostTrack }.count == 1)
        #expect(result.height == 3000)
        #expect(ScrollPages.sameRows(result, page, 0..<3000))
    }

    /// Review #1c: macOS 26 glass toolbars and blurred web headers let content show through.
    @Test func translucentStickyHeader() throws {
        let page = ScrollPages.textPage(seed: 24)
        let offsets = Array(stride(from: 0, through: 2400, by: 200))
        let (stitcher, steps) = run(page, offsets: offsets, overlays: [.header(height: 60, opacity: 0.82)])
        let result = try #require(stitcher.compose())

        #expect(!steps.contains(.lostTrack))
        #expect(result.height == 2900)
        #expect(ScrollPages.sameRows(result, page, 60..<2900))
    }

    /// Review #1a: a small animation (spinner, GIF strip) scrolls through the view.
    @Test func smallAnimationDoesNotBreakTheStitch() throws {
        let page = ScrollPages.textPage(seed: 25)
        let box = CGRect(x: 300, y: 1200, width: 200, height: 50)
        let offsets = Array(stride(from: 0, through: 2400, by: 100))
        let (stitcher, steps) = run(page, offsets: offsets, overlays: [.animatedBox(pageRect: box)])
        let result = try #require(stitcher.compose())

        #expect(!steps.contains(.lostTrack))
        #expect(ScrollPages.sameRows(result, page, 0..<1190))
        #expect(ScrollPages.sameRows(result, page, 1260..<2900))
    }

    /// Review #1: a lost frame (content changed in place while still) must not freeze the
    /// reference — once the view is still again, stitching goes on.
    @Test func stitchingResumesAfterContentChangedInPlace() throws {
        let page = ScrollPages.textPage(seed: 26)
        let box = CGRect(x: 40, y: 250, width: 500, height: 200) // big: covers much of the view
        let frames = [
            ScrollPages.frame(of: page, offset: 0, height: frameHeight, overlays: [.animatedBox(pageRect: box)], frameIndex: 0),
            ScrollPages.frame(of: page, offset: 0, height: frameHeight, overlays: [.animatedBox(pageRect: box)], frameIndex: 1),
            ScrollPages.frame(of: page, offset: 0, height: frameHeight, overlays: [.animatedBox(pageRect: box)], frameIndex: 2),
            ScrollPages.frame(of: page, offset: 150, height: frameHeight, overlays: [.animatedBox(pageRect: box)], frameIndex: 2),
            ScrollPages.frame(of: page, offset: 500, height: frameHeight, overlays: [], frameIndex: 3),
            ScrollPages.frame(of: page, offset: 700, height: frameHeight, overlays: [], frameIndex: 4),
        ]
        let stitcher = ScrollStitcher(firstFrame: frames[0])
        let steps = frames.dropFirst().map { stitcher.append($0) }

        #expect(steps.last == .added(200))
        #expect(stitcher.height == 1200)
    }

    /// Review #9: Bufr-Debug is what gets tested by hand; at 380 ms a frame it could stitch
    /// only ~2.6 of 12 frames a second and lost track constantly. A generous bound for a busy
    /// parallel test run.
    @Test func keepsUpEvenInDebugBuilds() throws {
        let page = ScrollPages.textPage(width: 2000, height: 5000, seed: 40)
        let frames = stride(from: 0, through: 1500, by: 150).map { ScrollPages.frame(of: page, offset: $0, height: 1400, overlays: []) }
        let stitcher = ScrollStitcher(firstFrame: frames[0])
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            for frame in frames.dropFirst() { _ = stitcher.append(frame) }
        }

        let perFrame = elapsed / (frames.count - 1)
        #expect(perFrame < .milliseconds(200), "\(perFrame) per 2000×1400 frame")
    }
}
