import CoreGraphics
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
        let payloads = try await service.barcodePayloads(in: TestImages.qrCode("https://example.com/bufr"))

        #expect(payloads == ["https://example.com/bufr"])
    }
}
