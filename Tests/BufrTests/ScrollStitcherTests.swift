import CoreGraphics
import Testing
@testable import Bufr

struct ScrollStitcherTests {
    private func stitch(_ page: CGImage, offsets: [Int], height: Int = 400, header: Int = 0, footer: Int = 0) -> (ScrollStitcher, [ScrollStitcher.Step]) {
        let frames = offsets.map { ScrollPages.frame(of: page, offset: $0, height: height, header: header, footer: footer) }
        let stitcher = ScrollStitcher(firstFrame: frames[0])
        let steps = frames.dropFirst().map { stitcher.append($0) }
        return (stitcher, steps)
    }

    @Test func steadyScrollRebuildsThePage() throws {
        let page = ScrollPages.page()
        let (stitcher, steps) = stitch(page, offsets: Array(stride(from: 0, through: 1500, by: 100)))
        let result = try #require(stitcher.compose())
        let expected = try #require(page.cropping(to: CGRect(x: 0, y: 0, width: page.width, height: 1900)))

        #expect(steps.allSatisfy { $0 == .added(100) })
        #expect(ScrollPages.sameRGBA(result, expected))
    }

    @Test func unevenStepsRebuildThePage() throws {
        let page = ScrollPages.page(seed: 2)
        let (stitcher, _) = stitch(page, offsets: [0, 37, 210, 211, 480, 650, 900])
        let result = try #require(stitcher.compose())
        let expected = try #require(page.cropping(to: CGRect(x: 0, y: 0, width: page.width, height: 1300)))

        #expect(ScrollPages.sameRGBA(result, expected))
    }

    @Test func stickyHeaderAndFooterAppearOnce() throws {
        let page = ScrollPages.page(seed: 3)
        let offsets = Array(stride(from: 0, through: 1200, by: 150))
        let (stitcher, _) = stitch(page, offsets: offsets, header: 40, footer: 30)
        let result = try #require(stitcher.compose())

        #expect(result.height == 400 + 1200) // header + scrolled content + footer, each once
        let top = try #require(ScrollPages.frame(of: page, offset: 0, height: 400, header: 40, footer: 30).cropping(to: CGRect(x: 0, y: 0, width: page.width, height: 370)))
        #expect(ScrollPages.sameRGBA(try #require(result.cropping(to: CGRect(x: 0, y: 0, width: page.width, height: 370))), top))
        let bottom = try #require(ScrollPages.frame(of: page, offset: 1200, height: 400, header: 40, footer: 30).cropping(to: CGRect(x: 0, y: 40, width: page.width, height: 360)))
        #expect(ScrollPages.sameRGBA(try #require(result.cropping(to: CGRect(x: 0, y: 1240, width: page.width, height: 360))), bottom))
    }

    /// Review Focus 1: blank margins match "by accident" at the same height in two frames.
    @Test func whiteMarginsAndStickyHeaderStitchExactly() throws {
        let page = ScrollPages.page(seed: 4, whiteBands: true)
        let offsets = Array(stride(from: 0, through: 1600, by: 120))
        let (stitcher, _) = stitch(page, offsets: offsets, header: 40)
        let result = try #require(stitcher.compose())
        let total = try #require(offsets.last) + 400
        let expectedBody = try #require(page.cropping(to: CGRect(x: 0, y: 40, width: page.width, height: total - 40)))

        #expect(result.height == total)
        #expect(ScrollPages.sameRGBA(try #require(result.cropping(to: CGRect(x: 0, y: 40, width: page.width, height: total - 40))), expectedBody))
    }

    @Test func scrollingUpIsIgnored() {
        let page = ScrollPages.page(seed: 5)
        let (stitcher, steps) = stitch(page, offsets: [0, 200, 100, 300])

        #expect(steps == [.added(200), .movedUp, .added(100)])
        #expect(stitcher.height == 700)
    }

    /// Review Focus 3
    @Test func lostTrackKeepsTheCanvasAndRecovers() throws {
        let page = ScrollPages.page(seed: 6)
        let (stitcher, steps) = stitch(page, offsets: [0, 100, 900, 200, 300])
        let result = try #require(stitcher.compose())
        let expected = try #require(page.cropping(to: CGRect(x: 0, y: 0, width: page.width, height: 700)))

        #expect(steps == [.added(100), .lostTrack, .added(100), .added(100)])
        #expect(ScrollPages.sameRGBA(result, expected))
    }

    @Test func sameFrameIsNoMovement() {
        let page = ScrollPages.page(seed: 7)
        let (_, steps) = stitch(page, offsets: [0, 0])

        #expect(steps == [.noMovement])
    }

    /// Review Focus 5
    @Test func stopsAtTheHeightLimit() throws {
        let page = ScrollPages.page(seed: 8)
        let frames = [0, 300, 600, 900].map { ScrollPages.frame(of: page, offset: $0, height: 400) }
        let stitcher = ScrollStitcher(firstFrame: frames[0], maxHeight: 1000)
        let steps = frames.dropFirst().map { stitcher.append($0) }

        #expect(steps == [.added(300), .added(300), .limitReached])
        #expect(try #require(stitcher.compose()).height == 1000)
    }
}
