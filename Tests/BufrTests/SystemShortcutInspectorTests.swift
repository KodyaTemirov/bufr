import AppKit
import Carbon.HIToolbox
import HotKey
import Testing
@testable import Bufr

struct SystemShortcutInspectorTests {
    let shiftCommand = Int(NSEvent.ModifierFlags([.shift, .command]).rawValue) // 1179648 in the plist

    @Test func missingIdMeansEnabledDefault() {
        let enabled = SystemShortcutInspector.enabledScreenshotShortcuts(in: [:])

        #expect(enabled.contains(HotKeyBinding(key: .three, modifiers: [.command, .shift])))
        #expect(enabled.contains(HotKeyBinding(key: .four, modifiers: [.command, .shift])))
        #expect(enabled.contains(HotKeyBinding(key: .five, modifiers: [.command, .shift])))
        #expect(enabled.count == 5)
    }

    @Test func unreadablePreferencesMeanAllDefaults() {
        #expect(SystemShortcutInspector.enabledScreenshotShortcuts(in: nil).count == 5)
    }

    @Test func disabledIdIsIgnored() {
        let enabled = SystemShortcutInspector.enabledScreenshotShortcuts(in: ["30": ["enabled": false]])

        #expect(!enabled.contains(HotKeyBinding(key: .four, modifiers: [.command, .shift])))
        #expect(enabled.contains(HotKeyBinding(key: .three, modifiers: [.command, .shift])))
    }

    @Test func reboundComboIsUsed() {
        let entry: [String: Any] = [
            "enabled": 1,
            "value": ["parameters": [65535, kVK_ANSI_1, shiftCommand], "type": "standard"],
        ]
        let enabled = SystemShortcutInspector.enabledScreenshotShortcuts(in: ["28": entry])

        #expect(enabled.contains(HotKeyBinding(key: .one, modifiers: [.command, .shift])))
        #expect(!enabled.contains(HotKeyBinding(key: .three, modifiers: [.command, .shift])))
    }
}

/// Lets a test change what "macOS currently uses" between calls.
@MainActor
final class SystemShortcutsBox {
    var combos: Set<HotKeyBinding> = []
}

@MainActor
@Suite(.serialized)
struct HotKeyManagerConflictTests {
    static let suiteName = "com.bufr.tests.conflicts"
    /// Unusual combo so a real Carbon registration during the test steals nothing
    let rareCombo = HotKeyBinding(key: .f12, modifiers: [.control, .option, .command])
    let system = SystemShortcutsBox()
    let manager: HotKeyManager

    init() {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        let box = system
        manager = HotKeyManager(store: HotKeyBindingStore(defaults: defaults), systemShortcuts: { box.combos })
    }

    @Test func comboUsedByMacOSIsNotRegistered() {
        system.combos = [rareCombo]

        manager.setBinding(rareCombo, for: .captureWindow)

        #expect(manager.blockedBySystem == [.captureWindow])
        #expect(!manager.isRegistered(.captureWindow))
        #expect(manager.bindings[.captureWindow] == rareCombo)
    }

    @Test func registersOnceMacOSReleasesCombo() {
        system.combos = [rareCombo]
        manager.setBinding(rareCombo, for: .captureWindow)

        system.combos = []
        manager.recheckSystemConflicts()

        #expect(manager.blockedBySystem.isEmpty)
        #expect(manager.isRegistered(.captureWindow))
        manager.setBinding(nil, for: .captureWindow)
    }

    @Test func duplicateBindingIsFound() {
        system.combos = [rareCombo]
        manager.setBinding(rareCombo, for: .captureWindow)

        #expect(manager.action(using: rareCombo, excluding: .capturePreviousArea) == .captureWindow)
        #expect(manager.action(using: rareCombo, excluding: .captureWindow) == nil)
    }

    @Test func recorderRejectsComboOfAnotherAction() throws {
        system.combos = [rareCombo]
        manager.setBinding(rareCombo, for: .captureWindow)
        let recording = HotKeyRecording(action: .capturePreviousArea, manager: manager)
        recording.start(in: nil)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.control, .option, .command], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: UInt16(kVK_F12)
        ))

        #expect(recording.handle(event) == nil)
        #expect(recording.isActive)
        #expect(manager.bindings[.capturePreviousArea] == nil)
        recording.stop()
    }

    @Test func activeBindingHidesComboOwnedByMacOS() {
        system.combos = [rareCombo]
        manager.setBinding(rareCombo, for: .captureWindow)
        #expect(manager.activeBinding(for: .captureWindow) == nil)

        system.combos = []
        manager.recheckSystemConflicts()
        #expect(manager.activeBinding(for: .captureWindow) == rareCombo)
        manager.setBinding(nil, for: .captureWindow)
    }

    /// The user turned the macOS shortcut back on: Bufr steps aside instead of both firing.
    @Test func stepsAsideWhenMacOSTakesComboBack() {
        manager.setBinding(rareCombo, for: .captureWindow)
        #expect(manager.isRegistered(.captureWindow))

        system.combos = [rareCombo]

        #expect(manager.confirmStillOwned(.captureWindow) == false)
        #expect(!manager.isRegistered(.captureWindow))
    }
}
