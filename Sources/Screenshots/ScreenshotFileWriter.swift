import Foundation

enum ScreenshotFileWriter {
    /// Writes `data` into `folder` (created if needed) under the first free name. Never overwrites.
    static func write(_ data: Data, to folder: URL, baseName: String, pathExtension: String = "png") throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        // A file may appear between the name check and the write; retry with the next free name
        var lastError: Error?
        for _ in 0..<5 {
            let name = ScreenshotFilenameFormatter.availableFilename(baseName: baseName, pathExtension: pathExtension) {
                fileManager.fileExists(atPath: folder.appendingPathComponent($0).path)
            }
            let url = folder.appendingPathComponent(name)
            do {
                try data.write(to: url, options: .withoutOverwriting)
                try? fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
                return url
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CocoaError(.fileWriteUnknown)
    }
}
