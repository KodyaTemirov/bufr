import AppKit

@MainActor
final class ClipboardPaster {

    /// Paste a clip item into the active application
    func paste(_ item: ClipItem, asPlainText: Bool = false) {
        Task {
            guard await write(item, asPlainText: asPlainText) else { return }
            try? await Task.sleep(for: .milliseconds(50))
            Self.simulatePaste()
        }
    }

    /// Copy item to clipboard without pasting
    func copyToClipboard(_ item: ClipItem, asPlainText: Bool = false) {
        Task {
            await write(item, asPlainText: asPlainText)
        }
    }

    // MARK: - Private

    /// Returns false when there was nothing to write (e.g. the image file is gone).
    @discardableResult
    private func write(_ item: ClipItem, asPlainText: Bool) async -> Bool {
        let pasteboard = NSPasteboard.general

        // Images ignore "plain text": pasting an empty string instead of the image helps nobody
        if item.contentType == .image {
            guard let imagePath = item.imagePath,
                  let data = await ImageStorage.shared.loadImageData(filename: imagePath)
            else { return false }
            return PasteboardWriter.writeImage(anyImageData: data, to: pasteboard)
        }

        if asPlainText {
            PasteboardWriter.writeText(item.textContent ?? "", to: pasteboard)
        } else {
            PasteboardWriter.write(item, to: pasteboard)
        }
        return true
    }

    /// Simulate Cmd+V keypress via CGEvent targeted to the frontmost app
    private static func simulatePaste() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let pid = frontApp.processIdentifier

        let source = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)

        // V key = virtual keycode 0x09
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else { return }

        keyDown.flags = CGEventFlags.maskCommand
        keyUp.flags = CGEventFlags.maskCommand

        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
    }
}
