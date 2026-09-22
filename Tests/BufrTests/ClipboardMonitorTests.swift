import AppKit
import Testing
@testable import Bufr

@MainActor
struct ClipboardMonitorTests {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.bufr.tests.\(UUID().uuidString)"))
    let store: ClipItemStore
    let monitor: ClipboardMonitor

    init() throws {
        let database = try AppDatabase.makeEmpty()
        store = ClipItemStore(database: database)
        let ingestor = ClipIngestor(
            store: store,
            imageStorage: ImageStorage(baseDirectory: try TestSupport.makeTempDirectory())
        )
        monitor = ClipboardMonitor(
            ingestor: ingestor,
            exclusionManager: ExclusionManager(database: database),
            pasteboard: pasteboard
        )
    }

    @Test func recordsExternalText() {
        pasteboard.clearContents()
        pasteboard.setString("external text", forType: .string)

        monitor.checkForChanges()

        #expect(store.items.first?.textContent == "external text")
        #expect(store.items.first?.origin == .clipboard)
    }

    @Test func ignoresConcealedContent() {
        pasteboard.clearContents()
        pasteboard.setString("secret", forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))

        monitor.checkForChanges()

        #expect(store.items.isEmpty)
    }

    @Test func unchangedPasteboardIsIgnored() {
        pasteboard.clearContents()
        pasteboard.setString("once", forType: .string)
        monitor.checkForChanges()
        monitor.checkForChanges()

        #expect(store.items.count == 1)
    }
}
