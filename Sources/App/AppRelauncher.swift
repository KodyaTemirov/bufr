import AppKit
import OSLog

private let logger = Logger(subsystem: "com.bufr.app", category: "AppRelauncher")

enum AppRelauncher {
    /// Quits and starts a fresh copy — macOS applies a new Screen Recording grant only to a new process.
    @MainActor
    static func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else {
            logger.error("Relaunch skipped: not running from an app bundle")
            return
        }

        // Wait for this process to exit, then reopen the bundle; values go in as arguments, not script text
        let script = #"while kill -0 "$0" 2>/dev/null; do sleep 0.2; done; open "$1""#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, String(ProcessInfo.processInfo.processIdentifier), bundlePath]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            logger.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
