import AppKit
import Carbon.HIToolbox
import HotKey
import Testing
@testable import Bufr

@MainActor
struct HotKeyBindingTests {
    let defaults: UserDefaults
    let store: HotKeyBindingStore

    init() {
        defaults = UserDefaults(suiteName: "com.bufr.tests.\(UUID().uuidString)")!
        store = HotKeyBindingStore(defaults: defaults)
    }

    @Test func defaultIsUsedWhenNothingStored() {
        #expect(store.binding(for: .togglePanel) == HotKeyAction.togglePanel.defaultBinding)
        #expect(store.binding(for: .togglePanel)?.displayString == "⇧⌘V")
    }

    @Test func savedBindingRoundTrips() {
        let binding = HotKeyBinding(key: .b, modifiers: [.command, .option])
        store.save(binding, for: .togglePanel)

        #expect(HotKeyBindingStore(defaults: defaults).binding(for: .togglePanel) == binding)
    }

    @Test func explicitlyDisabledStaysDisabled() {
        store.save(nil, for: .togglePanel)

        #expect(store.binding(for: .togglePanel) == nil)
    }

    @Test func resetRestoresDefault() {
        store.save(nil, for: .togglePanel)
        store.reset(.togglePanel)

        #expect(store.binding(for: .togglePanel) == HotKeyAction.togglePanel.defaultBinding)
    }

    /// Bufr 2.x stored raw NSEvent flags, including device-dependent bits (left/right keys).
    @Test func legacyBindingIsMigratedWithDeviceBitsStripped() {
        let raw = NSEvent.ModifierFlags([.command, .option]).rawValue | 0x128
        defaults.set(kVK_ANSI_B, forKey: "hotKeyCode")
        defaults.set(Int(raw), forKey: "hotKeyModifiers")

        store.migrateLegacyIfNeeded()

        let migrated = store.binding(for: .togglePanel)
        #expect(migrated == HotKeyBinding(carbonKeyCode: UInt32(kVK_ANSI_B), carbonModifiers: UInt32(cmdKey | optionKey)))
        #expect(migrated?.displayString == "⌥⌘B")
        #expect(defaults.object(forKey: "hotKeyCode") == nil)
        #expect(defaults.object(forKey: "hotKeyModifiers") == nil)
    }

    @Test func legacyMigrationDoesNotOverrideNewSettings() {
        let current = HotKeyBinding(key: .p, modifiers: [.control, .option])
        store.save(current, for: .togglePanel)
        defaults.set(kVK_ANSI_B, forKey: "hotKeyCode")
        defaults.set(Int(NSEvent.ModifierFlags.command.rawValue), forKey: "hotKeyModifiers")

        store.migrateLegacyIfNeeded()

        #expect(store.binding(for: .togglePanel) == current)
        #expect(defaults.object(forKey: "hotKeyCode") == nil)
    }

    @Test func bindingIgnoresIrrelevantModifiers() {
        let binding = HotKeyBinding(key: .v, modifiers: [.command, .shift, .capsLock, .function])

        #expect(binding == HotKeyBinding(key: .v, modifiers: [.command, .shift]))
    }

    @Test func keyboardShortcutForLettersOnly() {
        #expect(HotKeyBinding(key: .v, modifiers: [.command, .shift]).keyboardShortcut != nil)
        #expect(HotKeyBinding(key: .space, modifiers: [.option]).keyboardShortcut == nil)
    }
}
