import Foundation
import ServiceManagement
import SwiftUI

@MainActor @Observable
final class AppState {
    // MARK: - Services
    let database: AppDatabase
    let clipItemStore: ClipItemStore
    let clipboardMonitor: ClipboardMonitor
    let exclusionManager: ExclusionManager
    let hotKeyManager: HotKeyManager
    let panelManager: PanelManager
    let clipboardPaster: ClipboardPaster
    let pinboardStore: PinboardStore

    // MARK: - UI State
    var isPanelVisible = false
    var searchQuery = ""
    var selectedContentFilter: ContentType?

    // MARK: - Settings (persisted via UserDefaults)
    var historyLimit: Int {
        didSet { UserDefaults.standard.set(historyLimit, forKey: "historyLimit") }
    }
    var autoCleanupDays: Int {
        didSet { UserDefaults.standard.set(autoCleanupDays, forKey: "autoCleanupDays") }
    }
    var playCopySound: Bool {
        didSet {
            UserDefaults.standard.set(playCopySound, forKey: "playCopySound")
            clipboardMonitor.playCopySound = playCopySound
        }
    }
    var panelPosition: PanelPosition {
        didSet { UserDefaults.standard.set(panelPosition.rawValue, forKey: "panelPosition") }
    }
    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin()
        }
    }

    // MARK: - Onboarding
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    // MARK: - Hotkey Display
    var hotKeyDisplayString: String = "⌘⇧V"

    init(database: AppDatabase = .shared) {
        self.database = database

        // Load settings from UserDefaults
        let defaults = UserDefaults.standard
        self.historyLimit = defaults.object(forKey: "historyLimit") as? Int ?? 5000
        self.autoCleanupDays = defaults.object(forKey: "autoCleanupDays") as? Int ?? 30
        self.playCopySound = defaults.bool(forKey: "playCopySound")
        self.panelPosition = PanelPosition(rawValue: defaults.string(forKey: "panelPosition") ?? "") ?? .bottom
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")

        // Initialize services
        self.clipItemStore = ClipItemStore(database: database)
        self.exclusionManager = ExclusionManager(database: database)
        self.clipboardMonitor = ClipboardMonitor(
            clipItemStore: clipItemStore,
            exclusionManager: exclusionManager
        )
        self.hotKeyManager = HotKeyManager()
        self.panelManager = PanelManager()
        self.clipboardPaster = ClipboardPaster()
        self.pinboardStore = PinboardStore(database: database)

        // Load initial data
        do {
            try exclusionManager.loadExcludedApps()
            try clipItemStore.fetchItems()
            try pinboardStore.fetchPinboards()
            try clipItemStore.deleteOlderThan(days: autoCleanupDays)
            try clipItemStore.enforceHistoryLimit(historyLimit)
        } catch {
            print("Failed to initialize: \(error)")
        }

        // Sync sound setting
        clipboardMonitor.playCopySound = playCopySound

        // Start monitoring
        clipboardMonitor.startMonitoring()

        // Setup hotkey
        hotKeyManager.onTogglePanel = { [weak self] in
            self?.togglePanel()
        }
        hotKeyManager.register()

        // Panel close callback
        panelManager.onPanelClose = { [weak self] in
            self?.isPanelVisible = false
        }
    }

    // MARK: - Panel

    func togglePanel() {
        if isPanelVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        try? clipItemStore.fetchItems()

        let content = ClipPanelView()
            .environment(self)

        panelManager.showPanel(content: content, position: panelPosition)
        isPanelVisible = true
    }

    func hidePanel() {
        panelManager.hidePanel()
        isPanelVisible = false
    }

    // MARK: - Paste

    func pasteItem(_ item: ClipItem, asPlainText: Bool = false) {
        hidePanel()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.clipboardPaster.paste(item, asPlainText: asPlainText)
        }
    }

    // MARK: - History

    func clearHistory() {
        do {
            try clipItemStore.deleteAll()
            try clipItemStore.fetchItems()
        } catch {
            print("Failed to clear history: \(error)")
        }
    }

    func deleteAllBoards() {
        do {
            for board in pinboardStore.pinboards {
                try pinboardStore.delete(board)
            }
        } catch {
            print("Failed to delete boards: \(error)")
        }
    }

    func deleteItem(_ item: ClipItem) {
        do {
            if let imagePath = item.imagePath {
                Task {
                    await ImageStorage.shared.deleteImage(filename: imagePath, id: item.id)
                }
            }
            try clipItemStore.delete(item)
            try clipItemStore.fetchItems()
        } catch {
            print("Failed to delete item: \(error)")
        }
    }

    // MARK: - Hotkey

    func resetHotKey() {
        hotKeyManager.register()
        hotKeyDisplayString = "⌘⇧V"
    }

    // MARK: - Launch at Login

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}
