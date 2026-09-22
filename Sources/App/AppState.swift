import AppKit
import Foundation
import OSLog
import ServiceManagement
import SwiftUI

private let logger = Logger(subsystem: "com.bufr.app", category: "AppState")

@MainActor @Observable
final class AppState {
    static let shared = AppState()

    // MARK: - Services
    let database: AppDatabase
    let clipItemStore: ClipItemStore
    let clipIngestor: ClipIngestor
    let clipboardMonitor: ClipboardMonitor
    let exclusionManager: ExclusionManager
    let hotKeyManager: HotKeyManager
    let panelManager: PanelManager
    let clipboardPaster: ClipboardPaster
    let pinboardStore: PinboardStore
    var updater: AppUpdater

    // MARK: - UI State
    var isPanelVisible = false
    var searchQuery = ""
    var selectedContentFilter: ContentType?

    // MARK: - Settings (persisted via UserDefaults)
    var retentionPeriod: Int {  // дни: 1, 7, 30, 365, 0 (бесконечно)
        didSet {
            UserDefaults.standard.set(retentionPeriod, forKey: "retentionPeriod")
        }
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

    var pasteMode: PasteMode {
        didSet { UserDefaults.standard.set(pasteMode.rawValue, forKey: "pasteMode") }
    }
    var alwaysPastePlainText: Bool {
        didSet { UserDefaults.standard.set(alwaysPastePlainText, forKey: "alwaysPastePlainText") }
    }
    var copySound: CopySound {
        didSet { UserDefaults.standard.set(copySound.rawValue, forKey: "copySound") }
    }
    var appLanguage: AppLanguage {
        didSet { UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage") }
    }

    // MARK: - Onboarding
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    init(database: AppDatabase = .shared) {
        self.database = database

        // Load settings from UserDefaults
        let defaults = UserDefaults.standard
        // Миграция: если retentionPeriod ещё не задан, берём старый autoCleanupDays
        if defaults.object(forKey: "retentionPeriod") == nil,
           let oldDays = defaults.object(forKey: "autoCleanupDays") as? Int {
            let steps = [1, 7, 30, 365, 0]
            let closest = steps.min(by: { abs($0 - oldDays) < abs($1 - oldDays) }) ?? 30
            self.retentionPeriod = closest
        } else {
            self.retentionPeriod = defaults.object(forKey: "retentionPeriod") as? Int ?? 30
        }
        self.playCopySound = defaults.bool(forKey: "playCopySound")
        self.panelPosition = PanelPosition(rawValue: defaults.string(forKey: "panelPosition") ?? "") ?? .bottom
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.pasteMode = PasteMode(rawValue: defaults.string(forKey: "pasteMode") ?? "") ?? .activeApp
        self.alwaysPastePlainText = defaults.bool(forKey: "alwaysPastePlainText")
        self.copySound = CopySound(rawValue: defaults.string(forKey: "copySound") ?? "") ?? .tink
        self.appLanguage = AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "") ?? .system
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")

        // Initialize services
        self.clipItemStore = ClipItemStore(database: database)
        self.clipIngestor = ClipIngestor(store: clipItemStore)
        self.exclusionManager = ExclusionManager(database: database)
        self.clipboardMonitor = ClipboardMonitor(
            ingestor: clipIngestor,
            exclusionManager: exclusionManager
        )
        self.hotKeyManager = HotKeyManager()
        self.panelManager = PanelManager()
        self.clipboardPaster = ClipboardPaster()
        self.pinboardStore = PinboardStore(database: database)
        self.updater = AppUpdater()

        // Load initial data
        do {
            try exclusionManager.loadExcludedApps()
            try clipItemStore.fetchItems()
            try pinboardStore.fetchPinboards()
            if retentionPeriod > 0 {
                try clipItemStore.deleteOlderThan(days: retentionPeriod)
            }
        } catch {
            logger.error("Failed to initialize: \(error.localizedDescription, privacy: .public)")
        }

        // Sync sound setting
        clipboardMonitor.playCopySound = playCopySound

        // Start monitoring
        clipboardMonitor.startMonitoring()

        // Setup hotkeys
        hotKeyManager.onAction = { [weak self] action in
            self?.perform(action)
        }
        hotKeyManager.registerAll()

        // Panel close callback
        panelManager.onPanelClose = { [weak self] in
            PreviewWindowManager.shared.close()
            self?.isPanelVisible = false
        }

        // Check for updates on launch
        Task {
            await updater.checkOnLaunchIfNeeded()
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
        PreviewWindowManager.shared.close()
        panelManager.hidePanel()
        isPanelVisible = false
    }

    // MARK: - Paste

    func pasteItem(_ item: ClipItem, asPlainText: Bool = false) {
        hidePanel()
        bringToTop(item)

        let plainText = asPlainText || alwaysPastePlainText

        switch pasteMode {
        case .activeApp:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.clipboardPaster.paste(item, asPlainText: plainText)
            }
        case .clipboard:
            clipboardPaster.copyToClipboard(item, asPlainText: plainText)
        }
    }

    /// Copy without pasting (card context menu, menu bar list).
    func copyItem(_ item: ClipItem) {
        clipboardPaster.copyToClipboard(item)
        bringToTop(item)
    }

    /// Bufr's own pasteboard writes are not re-captured by the monitor,
    /// so a reused item is moved to the top explicitly.
    private func bringToTop(_ item: ClipItem) {
        do {
            try clipItemStore.touch(item)
        } catch {
            logger.error("Failed to move item to top: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - History

    func clearHistory() {
        do {
            try clipItemStore.deleteAll()
            Task { await ImageStorage.shared.deleteAllImages() }
            try clipItemStore.fetchItems()
        } catch {
            logger.error("Failed to clear history: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteAllBoards() {
        do {
            for board in pinboardStore.pinboards {
                try pinboardStore.delete(board)
            }
        } catch {
            logger.error("Failed to delete boards: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteItem(_ item: ClipItem) {
        do {
            if let imagePath = item.imagePath {
                Task {
                    await ImageStorage.shared.deleteAssets(imagePath: imagePath, itemId: item.id)
                }
            }
            try clipItemStore.delete(item)
            try clipItemStore.fetchItems()
        } catch {
            logger.error("Failed to delete item: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Hotkey

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .togglePanel:
            togglePanel()
        }
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
            logger.error("Failed to update launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }
}
