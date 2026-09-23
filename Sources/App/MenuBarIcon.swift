import AppKit

/// The logo in the menu bar: a template image, so macOS tints it for light, dark and
/// coloured menu bars like every other status item.
enum MenuBarIcon {
    @MainActor static let image: NSImage = {
        let image = resourceBundle().image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Bufr")
            ?? NSImage()
        image.isTemplate = true
        if image.size.width > 16 {
            image.size = NSSize(width: 16, height: 16)
        }
        return image
    }()
}
