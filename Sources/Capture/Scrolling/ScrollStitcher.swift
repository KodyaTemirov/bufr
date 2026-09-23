import Accelerate
import CoreGraphics
import Foundation

/// Glues frames of a region the user scrolls downwards into one tall image.
///
/// Each frame is compared with the last frame whose place in the result is known: rows that
/// stayed put at the top and bottom are a sticky header and footer, columns that stayed put
/// are a sidebar; in what moved, the vertical shift is found by matching row signatures, and
/// only the rows that scrolled into view are added. The header ends up once at the top (from
/// the first frame), the footer once at the bottom (from the last frame).
///
/// The heavy loops run on Accelerate, so stitching keeps up even in debug builds. Not
/// thread-safe: use from one queue or actor.
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

    /// Height of the part of the view that scrolls (without sticky header and footer), from
    /// the last comparison; "Auto" sizes its steps by it.
    private(set) var movingBandHeight: Int

    /// Rows this similar (mean difference of the brightness buckets, 0–255) count as equal
    private static let stillTolerance: Float = 1.0
    /// Rows this similar at the same place count as a (possibly translucent) sticky bar when
    /// choosing the part to match
    private static let barTolerance: Float = 8.0
    private static let matchTolerance: Float = 3.0
    /// The worst rows left out of a match score: a translucent bar or a small animation
    private static let trimmedShare: Float = 0.15

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
        movingBandHeight = frame.height
    }

    /// Height of the image `compose()` would return now.
    var height: Int {
        firstPending ? frameHeight : committed.height + (frameHeight - bottomRow)
    }

    func append(_ image: CGImage) -> Step {
        if limitHit { return .limitReached }
        guard let frame = Frame(image), frame.width == width, frame.height == frameHeight else { return .lostTrack }
        let h = frameHeight
        let comparison = Comparison(last, frame)

        // Rows unchanged at the same place: sticky header and footer
        var header = 0
        while header < h, comparison.sameRowDifference(header) <= Self.stillTolerance {
            header += 1
        }
        if header == h {
            last = frame
            return .noMovement
        }
        var footer = 0
        while footer < h - header, comparison.sameRowDifference(h - 1 - footer) <= Self.stillTolerance {
            footer += 1
        }
        // Only a sliver changed (a blinking caret, a counter): nothing scrolled
        guard h - header - footer >= h / 4 else {
            last = frame
            return .noMovement
        }

        // For matching, also leave out bars that are only nearly unchanged (translucent)
        var matchTop = header
        while matchTop < h - footer, comparison.sameRowDifference(matchTop) <= Self.barTolerance {
            matchTop += 1
        }
        var matchBottom = h - footer
        while matchBottom > matchTop, comparison.sameRowDifference(matchBottom - 1) <= Self.barTolerance {
            matchBottom -= 1
        }
        if matchBottom - matchTop < h / 4 {
            matchTop = header
            matchBottom = h - footer
        }

        guard let shift = findShift(comparison, top: matchTop, bottom: matchBottom) else {
            // Nothing matches, yet everything outside the changed rows is where it was: the
            // content changed in place (video, animation) without scrolling
            if header + footer >= h / 4, frame.isInformative(rows: 0..<header) || frame.isInformative(rows: (h - footer)..<h) {
                last = frame
                return .noMovement
            }
            return .lostTrack
        }
        if shift == 0 {
            last = frame
            return .noMovement
        }
        if shift < 0 { return .movedUp }
        movingBandHeight = h - header - footer
        return commit(frame, shift: shift, footer: footer)
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

    private func commit(_ frame: Frame, shift: Int, footer: Int) -> Step {
        let h = frameHeight
        let contentEnd = h - footer
        if firstPending {
            // The first frame's rows above its footer are content; its footer waits for the end
            appendToResult(last.pixels.rows(0..<contentEnd))
            bottomRow = contentEnd
            firstPending = false
        }

        // Where the committed content ends, in the new frame's rows
        let start = max(0, bottomRow - shift)
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

    /// The shift `d` of rows `top..<bottom`: new frame row `r` shows what the last frame showed
    /// at row `r + d` (positive = scrolled down). nil when no shift fits.
    private func findShift(_ comparison: Comparison, top: Int, bottom: Int) -> Int? {
        let band = bottom - top
        let minOverlap = max(band / 4, 8)
        guard band > minOverlap else { return nil }
        let limit = band - minOverlap

        // Coarse pass on one brightness value per row …
        var coarse: [(shift: Int, score: Float)] = []
        coarse.reserveCapacity(2 * limit + 1)
        for shift in -limit...limit {
            let from = top + max(0, -shift)
            let to = bottom - max(0, shift)
            coarse.append((shift, comparison.profileDifference(from: from, to: to, shift: shift)))
        }
        coarse.sort { $0.score < $1.score }

        // … then the best candidates whose overlap has content (a blank overlap matches
        // anything) on full signatures, ignoring the worst rows
        // The trimmed score decides whether a shift fits at all (it forgives a translucent bar
        // or a small animation); the full score ranks the ones that fit (it keeps the rows at
        // edges, which tell neighbouring shifts apart)
        var candidates: [(shift: Int, score: Float)] = []
        var checked = 0
        for (shift, _) in coarse where checked < 8 {
            let from = top + max(0, -shift)
            let to = bottom - max(0, shift)
            guard let scores = comparison.rowDifferences(from: from, to: to, shift: shift, trimmed: Self.trimmedShare) else {
                continue // nothing but blank rows overlap: can't tell
            }
            checked += 1
            if scores.trimmed <= Self.matchTolerance {
                candidates.append((shift, scores.full))
            }
        }
        guard let best = candidates.min(by: { $0.score < $1.score }) else {
            // A blank band (white page area) can't tell how far it moved
            return comparison.new.isInformative(rows: top..<bottom, profile: comparison.newProfile) ? nil : 0
        }
        // Repeating content can match equally at several shifts: then stay close to the
        // recent motion
        return candidates
            .filter { $0.score <= best.score * 1.05 + 0.05 }
            .min { abs($0.shift - lastShift) < abs($1.shift - lastShift) }?
            .shift
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

/// A frame's pixels and, per row, the mean brightness of `buckets` column groups.
private struct Frame {
    let pixels: RGBABuffer
    let buckets: Int
    let signature: [Float]

    var width: Int { pixels.width }
    var height: Int { pixels.height }

    init?(_ image: CGImage) {
        guard let pixels = RGBABuffer(image) else { return nil }
        self.init(pixels: pixels)
    }

    private init(pixels: RGBABuffer) {
        self.pixels = pixels
        buckets = max(1, min(128, pixels.width))
        signature = Self.signature(of: pixels, buckets: buckets)
    }

    static func empty(width: Int, height: Int) -> Frame {
        var pixels = RGBABuffer(width: max(width, 1))
        pixels.append(rows: ArraySlice([UInt8](repeating: 0, count: max(width, 1) * 4 * max(height, 1))))
        return Frame(pixels: pixels)
    }

    /// Enough rows that differ from each other for a match there to mean something (not a
    /// blank margin).
    func isInformative(rows: Range<Int>, profile: [Float]) -> Bool {
        guard let first = rows.first else { return false }
        let reference = profile[first]
        var distinct = 0
        for row in rows where abs(profile[row] - reference) > 2 {
            distinct += 1
            if distinct >= 4 { return true }
        }
        return false
    }

    func isInformative(rows: Range<Int>) -> Bool {
        isInformative(rows: rows, profile: Comparison.profile(signature, rows: height, columns: Array(0..<buckets), buckets: buckets))
    }

    /// Brightness (BT.601) per pixel, then each row averaged down to `buckets` columns.
    private static func signature(of pixels: RGBABuffer, buckets: Int) -> [Float] {
        let width = pixels.width
        let height = pixels.height
        guard width > 0, height > 0 else { return [] }
        var luma = [UInt8](repeating: 0, count: width * height)
        var small = [UInt8](repeating: 0, count: buckets * height)
        pixels.bytes.withUnsafeBufferPointer { source in
            luma.withUnsafeMutableBufferPointer { lumaPointer in
                small.withUnsafeMutableBufferPointer { smallPointer in
                    var rgba = vImage_Buffer(
                        data: UnsafeMutableRawPointer(mutating: source.baseAddress!),
                        height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4
                    )
                    var planar = vImage_Buffer(
                        data: lumaPointer.baseAddress!, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width
                    )
                    // Memory order R, G, B, A
                    let matrix: [Int16] = [299, 587, 114, 0]
                    vImageMatrixMultiply_ARGB8888ToPlanar8(&rgba, &planar, matrix, 1000, nil, 0, vImage_Flags(kvImageNoFlags))
                    var reduced = vImage_Buffer(
                        data: smallPointer.baseAddress!, height: vImagePixelCount(height), width: vImagePixelCount(buckets), rowBytes: buckets
                    )
                    vImageScale_Planar8(&planar, &reduced, nil, vImage_Flags(kvImageNoFlags))
                }
            }
        }
        var signature = [Float](repeating: 0, count: buckets * height)
        vDSP_vfltu8(small, 1, &signature, 1, vDSP_Length(buckets * height))
        return signature
    }
}

// MARK: - Comparison

/// Two frames prepared for matching: columns that stayed put in both (a sidebar, empty
/// margins) are left out, so only what scrolls decides the shift.
private struct Comparison {
    let old: Frame
    let new: Frame
    /// Differences at the same place, every bucket (for sticky bars)
    private let sameDifference: [Float]
    private let buckets: Int
    /// Signatures of the moving columns only, row-major
    private let oldMoving: [Float]
    private let newMoving: [Float]
    private let movingColumns: Int
    let oldProfile: [Float]
    let newProfile: [Float]
    private let oldHasContent: [Bool]
    private let newHasContent: [Bool]

    init(_ old: Frame, _ new: Frame) {
        self.old = old
        self.new = new
        let rows = new.height
        let buckets = new.buckets
        self.buckets = buckets
        let count = rows * buckets

        var difference = [Float](repeating: 0, count: count)
        vDSP_vsub(old.signature, 1, new.signature, 1, &difference, 1, vDSP_Length(count))
        vDSP_vabs(difference, 1, &difference, 1, vDSP_Length(count))
        sameDifference = difference

        // A column that is the same at the same place in (nearly) every row doesn't scroll
        var stillRows = [Int](repeating: 0, count: buckets)
        difference.withUnsafeBufferPointer { values in
            for row in 0..<rows {
                let base = row * buckets
                for column in 0..<buckets where values[base + column] <= 1 {
                    stillRows[column] += 1
                }
            }
        }
        var moving = (0..<buckets).filter { Double(stillRows[$0]) < Double(rows) * 0.97 }
        if moving.count < max(4, buckets / 8) {
            moving = Array(0..<buckets) // nearly everything is still: judge on all columns
        }
        movingColumns = moving.count
        oldMoving = Self.gather(old.signature, rows: rows, columns: moving, buckets: buckets)
        newMoving = Self.gather(new.signature, rows: rows, columns: moving, buckets: buckets)
        oldProfile = Self.profile(oldMoving, rows: rows, columns: Array(0..<moving.count), buckets: moving.count)
        newProfile = Self.profile(newMoving, rows: rows, columns: Array(0..<moving.count), buckets: moving.count)
        oldHasContent = Self.contentRows(oldMoving, rows: rows, columns: moving.count)
        newHasContent = Self.contentRows(newMoving, rows: rows, columns: moving.count)
    }

    /// Mean difference of one row with itself in the other frame, all columns.
    func sameRowDifference(_ row: Int) -> Float {
        var mean: Float = 0
        sameDifference.withUnsafeBufferPointer { values in
            vDSP_meanv(values.baseAddress! + row * buckets, 1, &mean, vDSP_Length(buckets))
        }
        return mean
    }

    /// Mean difference of the row brightness profiles over new rows `from..<to` against old
    /// rows shifted by `shift`.
    func profileDifference(from: Int, to: Int, shift: Int) -> Float {
        let count = to - from
        guard count > 0 else { return .infinity }
        var difference = [Float](repeating: 0, count: count)
        var sum: Float = 0
        newProfile.withUnsafeBufferPointer { newValues in
            oldProfile.withUnsafeBufferPointer { oldValues in
                vDSP_vsub(oldValues.baseAddress! + from + shift, 1, newValues.baseAddress! + from, 1, &difference, 1, vDSP_Length(count))
            }
        }
        vDSP_svemg(difference, 1, &sum, vDSP_Length(count))
        return sum / Float(count)
    }

    /// Mean row difference on the moving columns over the rows that have content in either
    /// frame (blank rows match anything and would water a conflict down): in full, and without
    /// the worst `trimmed` share. nil when fewer than 4 rows have content.
    func rowDifferences(from: Int, to: Int, shift: Int, trimmed: Float) -> (full: Float, trimmed: Float)? {
        let rows = to - from
        guard rows > 0 else { return nil }
        let columns = movingColumns
        let count = rows * columns
        var difference = [Float](repeating: 0, count: count)
        newMoving.withUnsafeBufferPointer { newValues in
            oldMoving.withUnsafeBufferPointer { oldValues in
                vDSP_vsub(oldValues.baseAddress! + (from + shift) * columns, 1, newValues.baseAddress! + from * columns, 1, &difference, 1, vDSP_Length(count))
            }
        }
        vDSP_vabs(difference, 1, &difference, 1, vDSP_Length(count))
        // Row means: difference (rows × columns) · 1/columns (columns × 1)
        let weights = [Float](repeating: 1 / Float(columns), count: columns)
        var rowMeans = [Float](repeating: 0, count: rows)
        vDSP_mmul(difference, 1, weights, 1, &rowMeans, 1, vDSP_Length(rows), 1, vDSP_Length(columns))

        var scored: [Float] = []
        scored.reserveCapacity(rows)
        for index in 0..<rows where newHasContent[from + index] || oldHasContent[from + index + shift] {
            scored.append(rowMeans[index])
        }
        guard scored.count >= 4 else { return nil }
        var full: Float = 0
        vDSP_meanv(scored, 1, &full, vDSP_Length(scored.count))
        vDSP_vsort(&scored, vDSP_Length(scored.count), 1)
        let kept = max(1, Int(Float(scored.count) * (1 - trimmed)))
        var trimmedMean: Float = 0
        vDSP_meanv(scored, 1, &trimmedMean, vDSP_Length(kept))
        return (full, trimmedMean)
    }

    /// Per row: the moving columns are not all one shade.
    private static func contentRows(_ signature: [Float], rows: Int, columns: Int) -> [Bool] {
        var result = [Bool](repeating: false, count: rows)
        signature.withUnsafeBufferPointer { values in
            for row in 0..<rows {
                var low: Float = 0
                var high: Float = 0
                vDSP_minv(values.baseAddress! + row * columns, 1, &low, vDSP_Length(columns))
                vDSP_maxv(values.baseAddress! + row * columns, 1, &high, vDSP_Length(columns))
                result[row] = high - low > 8
            }
        }
        return result
    }

    private static func gather(_ signature: [Float], rows: Int, columns: [Int], buckets: Int) -> [Float] {
        if columns.count == buckets { return signature }
        var result = [Float](repeating: 0, count: rows * columns.count)
        signature.withUnsafeBufferPointer { source in
            result.withUnsafeMutableBufferPointer { target in
                for row in 0..<rows {
                    let sourceBase = row * buckets
                    let targetBase = row * columns.count
                    for (index, column) in columns.enumerated() {
                        target[targetBase + index] = source[sourceBase + column]
                    }
                }
            }
        }
        return result
    }

    /// Mean brightness per row over `columns`.
    static func profile(_ signature: [Float], rows: Int, columns: [Int], buckets: Int) -> [Float] {
        var profile = [Float](repeating: 0, count: rows)
        signature.withUnsafeBufferPointer { values in
            for row in 0..<rows {
                vDSP_meanv(values.baseAddress! + row * buckets, 1, &profile[row], vDSP_Length(buckets))
            }
        }
        return profile
    }
}
