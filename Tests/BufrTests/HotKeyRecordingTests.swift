import AppKit
import Carbon.HIToolbox
import Testing
@testable import Bufr

@MainActor
@Suite(.serialized)
struct HotKeyRecordingTests {
    let manager: HotKeyManager
    let window: NSWindow

    init() {
        let defaults = UserDefaults(suiteName: "com.bufr.tests.recording")!
        defaults.removePersistentDomain(forName: "com.bufr.tests.recording")
        manager = HotKeyManager(store: HotKeyBindingStore(defaults: defaults))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled, .closable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
    }

    /// The Settings window is reused, so SwiftUI's onDisappear never fires when it closes.
    @Test func closingTheWindowStopsRecording() {
        let recording = HotKeyRecording(action: .togglePanel, manager: manager)
        recording.start(in: window)
        #expect(recording.isActive)
        #expect(manager.isSuspended)

        window.close()

        #expect(!recording.isActive)
        #expect(!manager.isSuspended)
    }

    @Test func losingKeyStatusStopsRecording() {
        let recording = HotKeyRecording(action: .togglePanel, manager: manager)
        recording.start(in: window)

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)

        #expect(!recording.isActive)
        #expect(!manager.isSuspended)
    }

    @Test func escapeCancelsWithoutChangingBinding() throws {
        let recording = HotKeyRecording(action: .togglePanel, manager: manager)
        recording.start(in: window)
        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: UInt16(kVK_Escape)
        ))

        #expect(recording.handle(escape) == nil)
        #expect(!recording.isActive)
        #expect(manager.bindings[.togglePanel] == nil)
    }
}
