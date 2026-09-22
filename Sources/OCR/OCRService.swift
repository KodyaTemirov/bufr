import CoreGraphics
import Foundation
import Vision

/// Runs Vision work one request at a time. Concurrent requests in one process fail inside
/// Vision's runtime ("e5rt … failed"), e.g. background indexing racing a text capture.
actor OCRSerialQueue {
    static let shared = OCRSerialQueue()

    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task { () async throws -> T in
            await previous?.value
            return try await work()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}

/// On-device text and QR recognition (Vision). Nothing leaves the Mac.
struct OCRService: Sendable {
    /// Vision has no Uzbek model; Latin-script Uzbek is read by the Latin models
    var languages: [Locale.Language] = [Locale.Language(identifier: "ru-RU"), Locale.Language(identifier: "en-US")]

    func recognizeText(in image: CGImage) async throws -> String {
        let languages = languages
        return try await OCRSerialQueue.shared.run {
            try await Self.recognize(image, languages: languages)
        }
    }

    func barcodePayloads(in image: CGImage) async throws -> [String] {
        try await OCRSerialQueue.shared.run {
            let observations = try await DetectBarcodesRequest().perform(on: image)
            return observations.compactMap(\.payloadString)
        }
    }

    private static func recognize(_ image: CGImage, languages: [Locale.Language]) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true

        let observations = try await request.perform(on: image)
        let lines = observations.compactMap { observation -> OCRTextAssembler.Line? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return OCRTextAssembler.Line(
                text: text,
                box: CGRect(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height)
            )
        }
        return OCRTextAssembler.text(from: lines)
    }
}
