import AppKit

@MainActor
final class ClipboardPaster {

    /// Paste a clip item into the active application
    func paste(_ item: ClipItem, asPlainText: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if asPlainText {
            pasteboard.setString(item.textContent ?? "", forType: .string)
        } else {
            writeOriginalFormat(item, to: pasteboard)
        }

        // Small delay to let the panel hide and focus return to the previous app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Self.simulatePaste()
        }
    }

    /// Copy item to clipboard without pasting
    func copyToClipboard(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        writeOriginalFormat(item, to: pasteboard)
    }

    // MARK: - Private

    private func writeOriginalFormat(_ item: ClipItem, to pasteboard: NSPasteboard) {
        switch item.contentType {
        case .text, .color:
            pasteboard.setString(item.textContent ?? "", forType: .string)

        case .richText:
            if let richData = item.richContent {
                pasteboard.setData(richData, forType: .rtf)
            }
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }

        case .url:
            let urlString = item.textContent ?? ""
            pasteboard.setString(urlString, forType: .string)
            if let url = URL(string: urlString) {
                pasteboard.setString(url.absoluteString, forType: NSPasteboard.PasteboardType("public.url"))
            }

        case .image:
            if let imagePath = item.imagePath {
                Task {
                    if let image = await ImageStorage.shared.loadImage(filename: imagePath),
                       let tiffData = image.tiffRepresentation {
                        pasteboard.setData(tiffData, forType: .tiff)
                    }
                }
            }

        case .file:
            let paths = item.filePathsArray
            let urls = paths.compactMap { URL(fileURLWithPath: $0) }
            pasteboard.writeObjects(urls as [NSURL])
        }
    }

    /// Simulate Cmd+V keypress via CGEvent
    private static func simulatePaste() {
        let source = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)

        // V key = virtual keycode 0x09
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else { return }

        keyDown.flags = CGEventFlags.maskCommand
        keyUp.flags = CGEventFlags.maskCommand

        keyDown.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
