import AppKit
import HotKey
import Observation

/// What the controls panel shows.
@MainActor @Observable
final class ScrollingCaptureModel {
    enum Hint: Equatable {
        case start
        case slower
        case end
        case limit
        case none
    }

    /// Size of the long image so far, in pixels
    var pixelSize: CGSize = .zero
    var preview: CGImage?
    var isAuto = false
    var hint: Hint = .start
    /// "Auto" was asked for without Accessibility
    var autoUnavailable = false
}

/// One scrolling capture: frames of the region are stitched as they arrive (manual scrolling)
/// or after each automatic scroll step, until Done or Cancel.
@MainActor
final class ScrollingCaptureSession {
    let model = ScrollingCaptureModel()
    /// The stream stopped by itself (display unplugged, permission revoked, screens changed)
    private(set) var didFail = false
    var onOpenAccessibility: () -> Void = {}

    private let region: ScrollRegion
    private let source: ScrollFrameSource
    private let scroller: AutoScrolling
    private let stillFrameTimeout: Duration
    private let showsPanels: Bool
    private let worker: StitchWorker

    private var continuation: CheckedContinuation<CGImage?, Never>?
    private var ended = false
    private var isProcessing = false
    private var pendingFrame: CGImage?

    private var policy: AutoScrollPolicy
    private var settleTimer: Task<Void, Never>?
    private var movedSinceScroll = false
    private var lostTrackSinceScroll = false
    private var limitReached = false

    private var panels: ScrollingCapturePanels?
    private var keys: [HotKey] = []
    private var screenObserver: NSObjectProtocol?

    init(
        region: ScrollRegion,
        source: ScrollFrameSource,
        scroller: AutoScrolling,
        stillFrameTimeout: Duration = .milliseconds(450),
        maxHeight: Int = 30_000,
        showsPanels: Bool = true
    ) {
        self.region = region
        self.source = source
        self.scroller = scroller
        self.stillFrameTimeout = stillFrameTimeout
        self.showsPanels = showsPanels
        self.worker = StitchWorker(maxHeight: maxHeight)
        self.policy = AutoScrollPolicy(regionHeightPoints: region.localRect.height)
    }

    /// The long image, or nil when cancelled or failed.
    func run() async -> CGImage? {
        if showsPanels {
            presentUI()
        }
        let image = await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            self.continuation = continuation
            Task { await self.startSource() }
        }
        settleTimer?.cancel()
        await source.stop()
        dismissUI()
        return image
    }

    func finish() {
        guard !ended else { return }
        ended = true
        settleTimer?.cancel()
        let pending = pendingFrame
        pendingFrame = nil
        let worker = worker
        Task {
            if let pending {
                _ = await worker.append(pending)
            }
            complete(await worker.compose())
        }
    }

    func cancel() {
        guard !ended else { return }
        ended = true
        complete(nil)
    }

    func toggleAuto() {
        guard !ended else { return }
        if model.isAuto {
            model.isAuto = false
            settleTimer?.cancel()
            return
        }
        guard scroller.isAvailable else {
            model.autoUnavailable = true
            return
        }
        guard !limitReached else { return }
        model.autoUnavailable = false
        model.isAuto = true
        if model.hint == .end {
            model.hint = .none
        }
        policy = AutoScrollPolicy(regionHeightPoints: region.localRect.height)
        scrollStep()
    }

    // MARK: - Frames

    private func startSource() async {
        do {
            try await source.start(
                onFrame: { [weak self] frame in self?.receive(frame) },
                onFailure: { [weak self] _ in self?.fail() }
            )
        } catch {
            fail()
        }
    }

    private func receive(_ frame: CGImage) {
        guard !ended else { return }
        if model.isAuto {
            restartSettleTimer() // still scrolling: wait for the view to settle
        }
        if isProcessing {
            pendingFrame = frame // only the newest frame matters
            return
        }
        process(frame)
    }

    private func process(_ frame: CGImage) {
        isProcessing = true
        let worker = worker
        Task {
            let result = await worker.append(frame)
            handle(result)
            isProcessing = false
            if !ended, let next = pendingFrame {
                pendingFrame = nil
                process(next)
            }
        }
    }

    private func handle(_ result: StitchWorker.Result) {
        model.pixelSize = CGSize(width: result.width, height: result.height)
        model.preview = result.preview
        switch result.step {
        case let .added(rows)?:
            if rows > 0 {
                movedSinceScroll = true
                if model.hint != .limit { model.hint = .none }
            }
        case .lostTrack?:
            lostTrackSinceScroll = true
            model.hint = .slower
        case .limitReached?:
            limitReached = true
            model.hint = .limit
        case .noMovement?, .movedUp?, nil:
            break
        }
    }

    // MARK: - Auto

    private var scrollPoint: CGPoint {
        let rect = ScreenGeometry.cgRect(fromCocoa: region.cocoaRect, primaryHeight: DisplayInfo.primaryHeight)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private func scrollStep() {
        movedSinceScroll = false
        lostTrackSinceScroll = false
        scroller.scroll(by: policy.stepPoints, at: scrollPoint)
        restartSettleTimer()
    }

    private func restartSettleTimer() {
        settleTimer?.cancel()
        let delay = stillFrameTimeout
        settleTimer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.settled()
        }
    }

    /// No new frame for a while after a scroll step: the view has settled, or nothing moved
    /// (ScreenCaptureKit sends no frame for an unchanged picture).
    private func settled() {
        guard model.isAuto, !ended else { return }
        if isProcessing || pendingFrame != nil {
            restartSettleTimer()
            return
        }
        let step: ScrollStitcher.Step
        if limitReached {
            step = .limitReached
        } else if movedSinceScroll {
            step = .added(1)
        } else if lostTrackSinceScroll {
            step = .lostTrack
        } else {
            step = .noMovement
        }
        switch policy.record(step) {
        case .scrollAgain:
            scrollStep()
        case .reachedEnd:
            model.isAuto = false
            model.hint = .end
        case .stop:
            model.isAuto = false
        }
    }

    // MARK: - Ending

    private func fail() {
        guard !ended else { return }
        ended = true
        didFail = true
        complete(nil)
    }

    private func complete(_ image: CGImage?) {
        continuation?.resume(returning: image)
        continuation = nil
    }

    // MARK: - UI

    private func presentUI() {
        let panels = ScrollingCapturePanels(
            region: region, model: model,
            onAuto: { [weak self] in self?.toggleAuto() },
            onDone: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.cancel() },
            onOpenAccessibility: { [weak self] in self?.onOpenAccessibility() }
        )
        panels.show()
        self.panels = panels

        // The scrolled app keeps the keyboard; Return and Esc still end the capture
        let done = HotKey(key: .return, modifiers: [])
        done.keyDownHandler = { [weak self] in self?.finish() }
        let cancel = HotKey(key: .escape, modifiers: [])
        cancel.keyDownHandler = { [weak self] in self?.cancel() }
        keys = [done, cancel]

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fail()
            }
        }
    }

    private func dismissUI() {
        keys = []
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        panels?.close()
        panels = nil
    }
}

/// Stitches off the main thread, one frame at a time.
actor StitchWorker {
    struct Result: Sendable {
        /// nil for the first frame
        let step: ScrollStitcher.Step?
        let width: Int
        let height: Int
        let preview: CGImage?
    }

    private var stitcher: ScrollStitcher?
    private let maxHeight: Int

    init(maxHeight: Int) {
        self.maxHeight = maxHeight
    }

    func append(_ frame: CGImage) -> Result {
        guard let stitcher else {
            let first = ScrollStitcher(firstFrame: frame, maxHeight: maxHeight)
            stitcher = first
            return Result(step: nil, width: first.width, height: first.height, preview: first.preview)
        }
        let step = stitcher.append(frame)
        return Result(step: step, width: stitcher.width, height: stitcher.height, preview: stitcher.preview)
    }

    func compose() -> CGImage? {
        stitcher?.compose()
    }
}
