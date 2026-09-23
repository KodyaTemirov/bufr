import CoreGraphics
import Foundation

/// Glues frames of a region the user scrolls downwards into one tall image.
///
/// Each frame is compared with the last stitched one: rows that stayed put at the top and
/// bottom are a sticky header and footer; in the band between, the vertical shift is found
/// by matching row signatures, and only the rows that scrolled into view are added. The
/// header ends up once at the top (from the first frame), the footer once at the bottom
/// (from the last frame). Not thread-safe: use from one queue or actor.
final class ScrollStitcher {
    enum Step: Equatable {
        /// Rows added to the result (0 when nothing new was below the canvas yet)
        case added(Int)
        case noMovement
        /// Scrolled back up: ignored, the result only grows downwards
        case movedUp
        /// No overlap with the last stitched frame (scrolled too fast): frame skipped
        case lostTrack
        case limitReached
    }

    let width: Int
    private let frameHeight: Int
    private let maxHeight: Int
    private let previewWidth: Int

    /// Rows already in the result
    private var committed: RGBABuffer
    /// Small copy of `committed` for the live preview
    private var previewCanvas: RGBABuffer
    private var previewRowDebt: Double = 0
    private var last: Frame
    /// Row of `last` where the committed content ends; below it: not yet committed + footer
    private var bottomRow: Int
    private var firstPending = true
    private var lastShift = 0
    private var limitHit = false

    /// Rows this similar (mean difference of 64 brightness buckets, 0–255) count as equal
    private static let stillTolerance = 1.0
    private static let matchTolerance = 3.0

    init(firstFrame: CGImage, maxHeight: Int = 30_000, maxPixels: Int = 60_000_000, previewWidth: Int = 160) {
        let frame = Frame(firstFrame) ?? Frame.empty(width: firstFrame.width, height: firstFrame.height)
        width = frame.width
        frameHeight = frame.height
        self.maxHeight = max(frame.height, min(maxHeight, maxPixels / max(frame.width, 1)))
        self.previewWidth = max(1, min(previewWidth, frame.width))
        committed = RGBABuffer(width: frame.width, colorSpace: frame.pixels.colorSpace)
        previewCanvas = RGBABuffer(width: self.previewWidth, colorSpace: frame.pixels.colorSpace)
        last = frame
        bottomRow = 0
    }

    /// Height of the image `compose()` would return now.
    var height: Int {
        firstPending ? frameHeight : committed.height + (frameHeight - bottomRow)
    }

    func append(_ image: CGImage) -> Step {
        if limitHit { return .limitReached }
        guard let frame = Frame(image), frame.width == width, frame.height == frameHeight else { return .lostTrack }
        let h = frameHeight

        var header = 0
        while header < h, Self.rowDifference(last, header, frame, header) <= Self.stillTolerance {
            header += 1
        }
        if header == h { return .noMovement }
        var footer = 0
        while footer < h - header, Self.rowDifference(last, h - 1 - footer, frame, h - 1 - footer) <= Self.stillTolerance {
            footer += 1
        }
        // Only a sliver changed (a blinking caret, a counter): nothing scrolled
        guard h - header - footer >= h / 4 else { return .noMovement }

        guard let shift = findShift(to: frame, header: header, footer: footer) else { return .lostTrack }
        if shift == 0 { return .noMovement }
        if shift < 0 { return .movedUp }
        return commit(frame, shift: shift, header: header, footer: footer)
    }

    func compose() -> CGImage? {
        if firstPending { return last.pixels.makeImage() }
        var result = committed
        result.append(rows: last.pixels.rows(bottomRow..<frameHeight))
        return result.makeImage()
    }

    /// A small image of what is stitched so far (without the not-yet-committed tail).
    var preview: CGImage? {
        firstPending ? last.pixels.makeImage().flatMap { Self.scaled($0, toWidth: previewWidth) } : previewCanvas.makeImage()
    }

    // MARK: - Stitching

    private func commit(_ frame: Frame, shift: Int, header: Int, footer: Int) -> Step {
        let h = frameHeight
        let contentEnd = h - footer
        if firstPending {
            // The first frame's rows above its footer are content; its footer waits for the end
            appendToResult(last.pixels.rows(0..<contentEnd))
            bottomRow = contentEnd
            firstPending = false
        }

        // Where the committed content ends, in the new frame's rows
        let start = max(header, bottomRow - shift)
        var rows = max(0, contentEnd - start)
        let room = maxHeight - committed.height - (h - contentEnd)
        if rows > room {
            limitHit = true
            rows = max(0, room)
        }
        if rows > 0 {
            appendToResult(frame.pixels.rows(start..<(start + rows)))
        }
        last = frame
        bottomRow = limitHit ? contentEnd : start + rows
        lastShift = shift
        return limitHit ? .limitReached : .added(rows)
    }

    private func appendToResult(_ rows: ArraySlice<UInt8>) {
        committed.append(rows: rows)
        appendToPreview(rows)
    }

    private func appendToPreview(_ rows: ArraySlice<UInt8>) {
        let count = rows.count / (width * 4)
        let scale = Double(previewWidth) / Double(width)
        previewRowDebt += Double(count) * scale
        let target = Int(previewRowDebt)
        guard target > 0 else { return }
        previewRowDebt -= Double(target)

        var strip = RGBABuffer(width: width, colorSpace: committed.colorSpace)
        strip.append(rows: rows)
        guard let image = strip.makeImage(),
              let context = CGContext(
                data: nil, width: previewWidth, height: target, bitsPerComponent: 8, bytesPerRow: previewWidth * 4,
                space: committed.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: previewWidth, height: target))
        guard let data = context.data else { return }
        let bytes = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: previewWidth * 4 * target)
        previewCanvas.append(rows: ArraySlice(bytes))
    }

    /// The shift `d` of the moving band: new frame row `r` shows what the last frame showed at
    /// row `r + d` (positive = scrolled down). nil when no shift fits.
    private func findShift(to frame: Frame, header: Int, footer: Int) -> Int? {
        let top = header
        let bottom = frameHeight - footer
        let band = bottom - top
        let minOverlap = max(band / 4, 8)
        guard band > minOverlap else { return nil }
        let limit = band - minOverlap

        // Coarse pass on one brightness value per row, then the best few on full signatures
        var coarse: [(shift: Int, score: Double)] = []
        coarse.reserveCapacity(2 * limit + 1)
        for shift in -limit...limit {
            let from = top + max(0, -shift)
            let to = bottom - max(0, shift)
            var total = 0.0
            for row in from..<to {
                total += abs(Double(frame.profile[row]) - Double(last.profile[row + shift]))
            }
            coarse.append((shift, total / Double(to - from)))
        }
        coarse.sort { $0.score < $1.score }

        var candidates: [(shift: Int, score: Double)] = []
        for (shift, _) in coarse.prefix(8) {
            let from = top + max(0, -shift)
            let to = bottom - max(0, shift)
            guard frame.isInformative(rows: from..<to) else { continue }
            var total = 0.0
            for row in from..<to {
                total += Self.rowDifference(frame, row, last, row + shift)
            }
            let score = total / Double(to - from)
            if score <= Self.matchTolerance {
                candidates.append((shift, score))
            }
        }
        guard let best = candidates.min(by: { $0.score < $1.score }) else {
            // A blank band (white page area) can't tell how far it moved
            return frame.isInformative(rows: top..<bottom) ? nil : 0
        }
        // Repeating content can match at several shifts: stay close to the recent motion
        return candidates
            .filter { $0.score <= best.score + 0.5 }
            .min { abs($0.shift - lastShift) < abs($1.shift - lastShift) }?
            .shift
    }

    private static func rowDifference(_ a: Frame, _ rowA: Int, _ b: Frame, _ rowB: Int) -> Double {
        let buckets = Frame.buckets
        var total = 0
        let offsetA = rowA * buckets
        let offsetB = rowB * buckets
        for index in 0..<buckets {
            total += abs(Int(a.signature[offsetA + index]) - Int(b.signature[offsetB + index]))
        }
        return Double(total) / Double(buckets)
    }

    private static func scaled(_ image: CGImage, toWidth width: Int) -> CGImage? {
        let height = max(1, Int(Double(image.height) * Double(width) / Double(image.width)))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: image.colorSpace ?? RGBABuffer.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

// MARK: - Frame

private struct Frame {
    static let buckets = 64

    let pixels: RGBABuffer
    /// Per row: mean brightness of `buckets` column groups
    let signature: [UInt8]
    /// Per row: mean brightness
    let profile: [Float]

    var width: Int { pixels.width }
    var height: Int { pixels.height }

    init?(_ image: CGImage) {
        guard let pixels = RGBABuffer(image) else { return nil }
        self.init(pixels: pixels)
    }

    private init(pixels: RGBABuffer) {
        self.pixels = pixels
        let width = pixels.width
        let height = pixels.height
        let buckets = Self.buckets
        var signature = [UInt8](repeating: 0, count: height * buckets)
        var profile = [Float](repeating: 0, count: height)
        pixels.bytes.withUnsafeBufferPointer { bytes in
            for row in 0..<height {
                let rowStart = row * width * 4
                var rowTotal = 0
                for bucket in 0..<buckets {
                    let from = bucket * width / buckets
                    let to = max(from + 1, (bucket + 1) * width / buckets)
                    var total = 0
                    for x in from..<min(to, width) {
                        let p = rowStart + x * 4
                        total += (Int(bytes[p]) * 299 + Int(bytes[p + 1]) * 587 + Int(bytes[p + 2]) * 114) / 1000
                    }
                    let mean = total / max(1, min(to, width) - from)
                    signature[row * buckets + bucket] = UInt8(clamping: mean)
                    rowTotal += mean
                }
                profile[row] = Float(rowTotal) / Float(buckets)
            }
        }
        self.signature = signature
        self.profile = profile
    }

    static func empty(width: Int, height: Int) -> Frame {
        var pixels = RGBABuffer(width: max(width, 1))
        pixels.append(rows: ArraySlice([UInt8](repeating: 0, count: max(width, 1) * 4 * max(height, 1))))
        return Frame(pixels: pixels)
    }

    /// Enough different rows that a match there means something (not a blank margin).
    func isInformative(rows: Range<Int>) -> Bool {
        guard let first = rows.first else { return false }
        let reference = profile[first]
        var distinct = 0
        for row in rows where abs(profile[row] - reference) > 2 {
            distinct += 1
            if distinct >= 4 { return true }
        }
        return false
    }
}
