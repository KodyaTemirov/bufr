import CoreGraphics
import Foundation
import Testing
@testable import Bufr

/// Runs the real on-device Vision models.
struct OCRServiceTests {
    let service = OCRService()

    @Test func recognizesEnglishText() async throws {
        let text = try await service.recognizeText(in: TestImages.text("Hello Bufr 2026"))

        #expect(text.contains("Hello"))
        #expect(text.contains("Bufr"))
    }

    @Test func recognizesRussianText() async throws {
        let text = try await service.recognizeText(in: TestImages.text("Привет мир"))

        #expect(text.contains("Привет"))
    }

    @Test func blankImageHasNoText() async throws {
        #expect(try await service.recognizeText(in: TestImages.blank()) == "")
    }

    @Test func readsQRCode() async throws {
        let payloads = try await service.barcodes(in: TestImages.qrCode("https://example.com/bufr")).map(\.payload)

        #expect(payloads == ["https://example.com/bufr"])
    }

    /// Vision can fail a request while it compiles its models right after an update
    /// ("e5rt … failed"); one more attempt succeeds.
    @Test func transientFailureIsRetriedOnce() async throws {
        let calls = RecognitionCounter()

        let text = try await OCRService.retryingOnce(after: .zero) {
            if await calls.increment() == 1 { throw CocoaError(.featureUnsupported) }
            return "ok"
        }

        #expect(text == "ok")
        #expect(await calls.count == 2)
    }

    @Test func persistentFailureIsReported() async throws {
        let calls = RecognitionCounter()

        await #expect(throws: CocoaError.self) {
            _ = try await OCRService.retryingOnce(after: .zero) { () -> String in
                _ = await calls.increment()
                throw CocoaError(.featureUnsupported)
            }
        }
        #expect(await calls.count == 2)
    }
}
