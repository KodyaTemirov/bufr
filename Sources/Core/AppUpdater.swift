import CryptoKit
import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.bufr.app", category: "AppUpdater")

// MARK: - Models

struct GitHubRelease: Sendable {
    let tagName: String
    let version: AppVersion
    let htmlURL: String
    let body: String
    let zipAssetURL: String
    let zipAssetSize: Int64
    let sha256: String?
}

enum UpdateStatus: Equatable {
    case idle
    case checking
    case noUpdate
    case available(version: String)
    case downloading(progress: Double)
    case readyToInstall
    case installing
    case error(message: String)
}

enum UpdateError: LocalizedError {
    case extractionFailed(String)
    case noAppBundleFound
    case hashMismatch

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let msg): return "Ошибка распаковки: \(msg)"
        case .noAppBundleFound: return "Не найден .app в архиве"
        case .hashMismatch: return "Хэш файла не совпадает"
        }
    }
}

// MARK: - AppUpdater

@MainActor @Observable
final class AppUpdater {
    var status: UpdateStatus = .idle
    var latestRelease: GitHubRelease?
    var lastCheckDate: Date? {
        didSet {
            if let date = lastCheckDate {
                UserDefaults.standard.set(date, forKey: "lastUpdateCheckDate")
            }
        }
    }
    var autoCheckEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCheckEnabled, forKey: "autoCheckEnabled") }
    }

    private let repoOwner = "KodyaTemirov"
    private let repoName = "bufr"
    private var downloadTask: Task<Void, Never>?
    private var downloadedZipURL: URL?

    init() {
        self.autoCheckEnabled =
            UserDefaults.standard.object(forKey: "autoCheckEnabled") as? Bool ?? true
        self.lastCheckDate =
            UserDefaults.standard.object(forKey: "lastUpdateCheckDate") as? Date
    }

    // MARK: - Check for Updates

    func checkForUpdates() async {
        status = .checking

        do {
            let url = URL(
                string:
                    "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
            )!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                status = .error(message: "Не удалось проверить обновления")
                return
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let release = parseRelease(json) else {
                status = .error(message: "Не удалось разобрать данные релиза")
                return
            }

            guard let currentVersion = AppVersion.current else {
                status = .error(message: "Не удалось определить текущую версию")
                return
            }

            lastCheckDate = Date()

            if release.version > currentVersion {
                latestRelease = release
                status = .available(version: release.version.description)
            } else {
                status = .noUpdate
            }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            status = .error(message: "Ошибка проверки: \(error.localizedDescription)")
        }
    }

    // MARK: - Download Update

    func downloadUpdate() async {
        guard let release = latestRelease,
            let url = URL(string: release.zipAssetURL)
        else { return }

        status = .downloading(progress: 0)

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
            let totalSize = response.expectedContentLength

            let destDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("bufr_update_\(UUID().uuidString)")
            try FileManager.default.createDirectory(
                at: destDir, withIntermediateDirectories: true)
            let zipURL = destDir.appendingPathComponent("Bufr.app.zip")

            FileManager.default.createFile(atPath: zipURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: zipURL)

            var downloadedBytes: Int64 = 0
            var buffer = Data()
            let chunkSize = 65_536

            for try await byte in asyncBytes {
                buffer.append(byte)
                if buffer.count >= chunkSize {
                    handle.write(buffer)
                    downloadedBytes += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if totalSize > 0 {
                        status = .downloading(
                            progress: Double(downloadedBytes) / Double(totalSize))
                    }
                }
            }
            if !buffer.isEmpty {
                handle.write(buffer)
                downloadedBytes += Int64(buffer.count)
            }
            handle.closeFile()

            // Verify SHA-256 if available
            if let expectedHash = release.sha256 {
                let actualHash = try sha256Hash(of: zipURL)
                guard actualHash == expectedHash else {
                    status = .error(message: "Ошибка верификации: хэш файла не совпадает")
                    try? FileManager.default.removeItem(at: destDir)
                    return
                }
                logger.info("SHA256 verification passed")
            }

            downloadedZipURL = zipURL
            status = .readyToInstall
        } catch {
            logger.error("Download failed: \(error.localizedDescription, privacy: .public)")
            status = .error(message: "Ошибка загрузки: \(error.localizedDescription)")
        }
    }

    // MARK: - Install and Relaunch

    func installAndRelaunch() {
        guard let zipURL = downloadedZipURL else { return }

        status = .installing

        let currentAppPath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier

        // Build a single shell script that does everything:
        // 1. Wait for app to exit  2. Extract ZIP  3. Replace app  4. Remove quarantine  5. Cleanup  6. Relaunch
        let extractDir = zipURL.deletingLastPathComponent()
            .appendingPathComponent("extracted").path
        let zipPath = zipURL.path
        let backupPath = (currentAppPath as NSString)
            .deletingLastPathComponent + "/Bufr_backup.app"
        let tempDir = zipURL.deletingLastPathComponent().path

        let script = """
        # Wait for the app process to exit
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        set -e
        mkdir -p "\(extractDir)"
        /usr/bin/ditto -x -k "\(zipPath)" "\(extractDir)"
        APP=$(/usr/bin/find "\(extractDir)" -maxdepth 1 -name "*.app" -print -quit)
        if [ -z "$APP" ]; then exit 1; fi
        rm -rf "\(backupPath)"
        mv "\(currentAppPath)" "\(backupPath)"
        mv "$APP" "\(currentAppPath)"
        /usr/bin/xattr -cr "\(currentAppPath)" 2>/dev/null || true
        rm -rf "\(backupPath)"
        rm -rf "\(tempDir)"
        open "\(currentAppPath)"
        """

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script]
            try process.run()

            logger.info("Update script launched, force-quitting app...")

            // Force quit — terminate(nil) can be blocked by SwiftUI sheets
            exit(0)
        } catch {
            logger.error("Install failed: \(error.localizedDescription, privacy: .public)")
            status = .error(message: "Ошибка установки: \(error.localizedDescription)")
        }
    }

    // MARK: - Cancel

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        status = .idle
    }

    // MARK: - Auto-check on Launch

    func checkOnLaunchIfNeeded() async {
        guard autoCheckEnabled else { return }

        // Throttle: max once per hour
        if let lastCheck = lastCheckDate,
            Date().timeIntervalSince(lastCheck) < 3600
        {
            return
        }

        // Delay so app UI appears first
        try? await Task.sleep(for: .seconds(3))

        await checkForUpdates()
    }

    // MARK: - Private Helpers

    private func parseRelease(_ json: [String: Any]?) -> GitHubRelease? {
        guard let json,
            let tagName = json["tag_name"] as? String,
            let version = AppVersion(string: tagName),
            let htmlURL = json["html_url"] as? String,
            let assets = json["assets"] as? [[String: Any]]
        else {
            return nil
        }

        let body = json["body"] as? String ?? ""

        // Find .zip asset
        guard
            let zipAsset = assets.first(where: {
                ($0["name"] as? String)?.hasSuffix(".zip") == true
            }),
            let downloadURL = zipAsset["browser_download_url"] as? String,
            let size = zipAsset["size"] as? Int64
        else {
            return nil
        }

        let sha256 = parseSHA256(from: body)

        return GitHubRelease(
            tagName: tagName,
            version: version,
            htmlURL: htmlURL,
            body: body,
            zipAssetURL: downloadURL,
            zipAssetSize: size,
            sha256: sha256
        )
    }

    private func parseSHA256(from body: String) -> String? {
        let lines = body.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("sha256:") {
                let hash = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
                if hash.count == 64 {
                    return hash.lowercased()
                }
            }
        }
        return nil
    }

    private nonisolated func sha256Hash(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private nonisolated func runProcess(executable: String, arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw UpdateError.extractionFailed(errorMsg)
        }
        return process.terminationStatus
    }
}
