import Foundation
import ImageIO
import Testing
@testable import Bufr

struct ScreenshotFilenameFormatterTests {
    let date = Date(timeIntervalSince1970: 1_790_172_312) // 2026-09-23 14:05:12 UTC
    let utc = TimeZone(identifier: "UTC")!

    @Test func baseNameUsesPOSIXDigits() {
        let name = ScreenshotFilenameFormatter.baseName(prefix: "Screenshot", connector: "at", date: date, timeZone: utc)

        #expect(name == "Screenshot 2026-09-23 at 14.05.12")
    }

    @Test func prefixIsSanitized() {
        let name = ScreenshotFilenameFormatter.baseName(prefix: " Shot/2: x ", connector: "в", date: date, timeZone: utc)

        #expect(name == "Shot-2- x 2026-09-23 в 14.05.12")
    }

    @Test func emptyPrefixIsDropped() {
        let name = ScreenshotFilenameFormatter.baseName(prefix: "  ", connector: "at", date: date, timeZone: utc)

        #expect(name == "2026-09-23 at 14.05.12")
    }

    @Test func collisionsGetANumber() {
        let taken: Set = ["X.png", "X (2).png"]
        let name = ScreenshotFilenameFormatter.availableFilename(baseName: "X") { taken.contains($0) }

        #expect(name == "X (3).png")
    }
}

struct ScreenshotFileWriterTests {
    @Test func createsMissingFolder() throws {
        let folder = try TestSupport.makeTempDirectory().appendingPathComponent("Pictures/Bufr")

        let url = try ScreenshotFileWriter.write(Data([1, 2, 3]), to: folder, baseName: "Shot")

        #expect(url.lastPathComponent == "Shot.png")
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
    }

    @Test func neverOverwrites() throws {
        let folder = try TestSupport.makeTempDirectory()

        let first = try ScreenshotFileWriter.write(Data([1]), to: folder, baseName: "Shot")
        let second = try ScreenshotFileWriter.write(Data([2]), to: folder, baseName: "Shot")

        #expect(second.lastPathComponent == "Shot (2).png")
        #expect(try Data(contentsOf: first) == Data([1]))
        #expect(try Data(contentsOf: second) == Data([2]))
    }
}

struct ImageEncoderPNGTests {
    private func dpi(of data: Data) -> Double? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return (props[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue
    }

    @Test func pngCarriesRetinaDPI() throws {
        let data = try #require(ImageEncoder.pngData(from: TestImages.cgImage(width: 4, height: 3), pointScale: 2, downscaleToOneX: false))

        #expect(dpi(of: data) == 144)
        #expect(ImageEncoder.normalizedPNG(data)?.pixelWidth == 4)
    }

    @Test func downscaleHalvesPixels() throws {
        let data = try #require(ImageEncoder.pngData(from: TestImages.cgImage(width: 8, height: 6), pointScale: 2, downscaleToOneX: true))

        #expect(ImageEncoder.normalizedPNG(data)?.pixelWidth == 4)
        #expect(ImageEncoder.normalizedPNG(data)?.pixelHeight == 3)
        #expect(dpi(of: data) == 72)
    }
}

@MainActor
@Suite(.serialized)
struct ScreenshotSettingsTests {
    static let suiteName = "com.bufr.tests.screenshots"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    @Test func defaultsMatchSpec() {
        let settings = ScreenshotSettings(defaults: defaults)

        #expect(settings.saveFolder == ScreenshotSettings.defaultSaveFolder)
        #expect(settings.saveFolder.path.hasSuffix("/Pictures/Bufr"))
        #expect(settings.copyToClipboard)
        #expect(settings.playSound)
        #expect(settings.windowShadow)
        #expect(!settings.includeCursor)
        #expect(!settings.retinaAtOneX)
        #expect(settings.customFilenamePrefix == nil)
        #expect(settings.ocrIndexingEnabled)
    }

    @Test func afterCaptureDefaults() {
        let settings = ScreenshotSettings(defaults: defaults)

        #expect(settings.afterCapture == .quickAccess)
        #expect(settings.quickAccessPosition == .bottomLeft)
        #expect(settings.quickAccessAutoClose == 10)
    }

    @Test func afterCaptureSettingsPersist() {
        let settings = ScreenshotSettings(defaults: defaults)
        settings.afterCapture = .pin
        settings.quickAccessPosition = .bottomRight
        settings.quickAccessAutoClose = 0

        let reloaded = ScreenshotSettings(defaults: defaults)
        #expect(reloaded.afterCapture == .pin)
        #expect(reloaded.quickAccessPosition == .bottomRight)
        #expect(reloaded.quickAccessAutoClose == 0)
    }

    @Test func changesPersist() {
        let settings = ScreenshotSettings(defaults: defaults)
        settings.saveFolder = URL(fileURLWithPath: "/tmp/shots")
        settings.copyToClipboard = false
        settings.customFilenamePrefix = "Bug"

        let reloaded = ScreenshotSettings(defaults: defaults)
        #expect(reloaded.saveFolder.path == "/tmp/shots")
        #expect(!reloaded.copyToClipboard)
        #expect(reloaded.filenamePrefix == "Bug")
    }
}
