import AppKit
import Foundation
import GRDB
import OSLog
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.bufr.app", category: "PinboardExport")

enum PinboardExportError: LocalizedError {
    case noItemsToExport
    case zipCreationFailed(String)
    case zipExtractionFailed(String)
    case invalidArchive
    case unsupportedVersion(Int)
    case jsonDecodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noItemsToExport:
            return "Доска пуста, нечего экспортировать"
        case .zipCreationFailed(let msg):
            return "Ошибка создания архива: \(msg)"
        case .zipExtractionFailed(let msg):
            return "Ошибка распаковки архива: \(msg)"
        case .invalidArchive:
            return "Некорректный файл .bufr"
        case .unsupportedVersion(let v):
            return "Неподдерживаемая версия формата: \(v)"
        case .jsonDecodingFailed(let e):
            return "Ошибка чтения данных: \(e.localizedDescription)"
        }
    }
}

enum PinboardExportService {
    private static let currentVersion = 1

    // MARK: - Export

    @MainActor
    static func exportPinboard(
        _ pinboard: Pinboard,
        database: AppDatabase,
        imageStorage: ImageStorage
    ) async throws -> URL {
        let (clipItems, pinboardItems) = try fetchBoardData(pinboard: pinboard, database: database)

        guard !clipItems.isEmpty else {
            throw PinboardExportError.noItemsToExport
        }

        let saveURL = exportDirectory().appendingPathComponent("\(pinboard.name).bufr")

        try await packageExport(
            pinboard: pinboard,
            clipItems: clipItems,
            pinboardItems: pinboardItems,
            to: saveURL,
            imageStorage: imageStorage
        )

        logger.info("Exported pinboard '\(pinboard.name)' with \(clipItems.count) items")
        return saveURL
    }

    // MARK: - Export All

    @MainActor
    static func exportAllPinboards(
        pinboards: [Pinboard],
        database: AppDatabase,
        imageStorage: ImageStorage
    ) async throws -> URL {
        guard !pinboards.isEmpty else {
            throw PinboardExportError.noItemsToExport
        }

        let saveURL = exportDirectory().appendingPathComponent("bufr_boards.bufr")

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("bufr_export_all_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let imagesDir = tempDir.appendingPathComponent("images")
        try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        var boardExports: [PinboardExport] = []

        for pinboard in pinboards {
            let (clipItems, pinboardItems) = try fetchBoardData(pinboard: pinboard, database: database)
            guard !clipItems.isEmpty else { continue }

            let junctionLookup = Dictionary(
                pinboardItems.map { ($0.clipId, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            let exportedItems: [ExportedClipItem] = clipItems.compactMap { clip in
                guard let junction = junctionLookup[clip.id] else { return nil }
                return ExportedClipItem(
                    clipItem: clip,
                    sortOrder: junction.sortOrder,
                    addedAt: junction.addedAt
                )
            }

            boardExports.append(PinboardExport(
                version: currentVersion,
                exportDate: Date(),
                pinboard: pinboard,
                items: exportedItems
            ))

            // Copy images
            for clip in clipItems {
                guard let imagePath = clip.imagePath, !imagePath.isEmpty else { continue }
                let destPath = imagesDir.appendingPathComponent(imagePath)
                guard !fm.fileExists(atPath: destPath.path) else { continue }
                if let data = await imageStorage.loadImageData(filename: imagePath) {
                    try data.write(to: destPath)
                }
            }
        }

        guard !boardExports.isEmpty else {
            throw PinboardExportError.noItemsToExport
        }

        let bulk = BulkPinboardExport(
            version: currentVersion,
            exportDate: Date(),
            pinboards: boardExports
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(bulk)
        try jsonData.write(to: tempDir.appendingPathComponent("pinboards.json"))

        try runDitto(arguments: ["-c", "-k", "--sequesterRsrc", tempDir.path, saveURL.path])

        logger.info("Exported \(boardExports.count) pinboards")
        return saveURL
    }

    // MARK: - Import All

    @MainActor
    static func importAllPinboards(
        database: AppDatabase,
        pinboardStore: PinboardStore,
        imageStorage: ImageStorage
    ) async throws -> [Pinboard] {
        // 1. Show NSOpenPanel
        let panel = NSOpenPanel()
        panel.title = "Импортировать доски"
        if let bufrType = UTType(filenameExtension: "bufr") {
            panel.allowedContentTypes = [bufrType]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        let response = runModalPanel(panel)
        guard response == .OK, let fileURL = panel.url else { return [] }

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("bufr_import_all_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        try runDitto(arguments: ["-x", "-k", fileURL.path, tempDir.path])

        // Try bulk format first (pinboards.json), fall back to single board (pinboard.json)
        let bulkJsonURL = tempDir.appendingPathComponent("pinboards.json")
        let singleJsonURL = tempDir.appendingPathComponent("pinboard.json")

        if fm.fileExists(atPath: bulkJsonURL.path) {
            // Bulk import
            let jsonData = try Data(contentsOf: bulkJsonURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let bulk: BulkPinboardExport
            do {
                bulk = try decoder.decode(BulkPinboardExport.self, from: jsonData)
            } catch {
                throw PinboardExportError.jsonDecodingFailed(error)
            }

            guard bulk.version <= currentVersion else {
                throw PinboardExportError.unsupportedVersion(bulk.version)
            }

            let imagesImportDir = tempDir.appendingPathComponent("images")
            var importedBoards: [Pinboard] = []

            for boardExport in bulk.pinboards {
                let newBoard = try await importSingleBoard(
                    export: boardExport,
                    imagesDir: imagesImportDir,
                    database: database,
                    pinboardStore: pinboardStore,
                    imageStorage: imageStorage
                )
                importedBoards.append(newBoard)
            }

            try pinboardStore.fetchPinboards()
            logger.info("Imported \(importedBoards.count) pinboards")
            return importedBoards
        } else if fm.fileExists(atPath: singleJsonURL.path) {
            // Single board — fall back to existing logic
            let newBoard = try await unpackageImport(
                from: fileURL,
                database: database,
                pinboardStore: pinboardStore,
                imageStorage: imageStorage
            )
            return [newBoard]
        } else {
            throw PinboardExportError.invalidArchive
        }
    }

    // MARK: - Private: Import single board from export data

    @MainActor
    private static func importSingleBoard(
        export: PinboardExport,
        imagesDir: URL,
        database: AppDatabase,
        pinboardStore: PinboardStore,
        imageStorage: ImageStorage
    ) async throws -> Pinboard {
        let fm = FileManager.default

        let newBoard = try pinboardStore.create(
            name: export.pinboard.name,
            icon: export.pinboard.icon,
            color: export.pinboard.color
        )

        for exportedItem in export.items {
            let clip = exportedItem.clipItem
            let existingClip = try findClipByHash(clip.hash, database: database)
            let clipIdToUse: UUID

            if let existing = existingClip {
                clipIdToUse = existing.id
            } else {
                let clipToInsert: ClipItem
                if let imagePath = clip.imagePath, !imagePath.isEmpty,
                   fm.fileExists(atPath: imagesDir.appendingPathComponent(imagePath).path) {
                    let imageData = try Data(contentsOf: imagesDir.appendingPathComponent(imagePath))
                    let savedFilename = try await imageStorage.saveImage(imageData, id: clip.id)
                    clipToInsert = ClipItem(
                        id: clip.id,
                        contentType: clip.contentType,
                        textContent: clip.textContent,
                        richContent: clip.richContent,
                        imagePath: savedFilename,
                        filePaths: clip.filePaths,
                        sourceAppId: clip.sourceAppId,
                        sourceAppName: clip.sourceAppName,
                        createdAt: clip.createdAt,
                        isPinned: clip.isPinned,
                        isFavorite: clip.isFavorite,
                        hash: clip.hash,
                        customTitle: clip.customTitle
                    )
                } else {
                    clipToInsert = clip
                }

                try insertClip(clipToInsert, database: database)
                clipIdToUse = clipToInsert.id
            }

            try insertJunction(
                pinboardId: newBoard.id,
                clipId: clipIdToUse,
                sortOrder: exportedItem.sortOrder,
                addedAt: exportedItem.addedAt,
                database: database
            )
        }

        return newBoard
    }

    // MARK: - Import

    @MainActor
    static func importPinboard(
        database: AppDatabase,
        pinboardStore: PinboardStore,
        imageStorage: ImageStorage
    ) async throws -> Pinboard? {
        // 1. Show NSOpenPanel
        let panel = NSOpenPanel()
        panel.title = "Импортировать доску"
        if let bufrType = UTType(filenameExtension: "bufr") {
            panel.allowedContentTypes = [bufrType]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        let response = runModalPanel(panel)
        guard response == .OK, let fileURL = panel.url else { return nil }

        // 2. Unpackage and import
        let newBoard = try await unpackageImport(
            from: fileURL,
            database: database,
            pinboardStore: pinboardStore,
            imageStorage: imageStorage
        )

        logger.info("Imported pinboard '\(newBoard.name)'")
        return newBoard
    }

    // MARK: - Private: Fetch

    private static func fetchBoardData(
        pinboard: Pinboard,
        database: AppDatabase
    ) throws -> ([ClipItem], [PinboardItem]) {
        try database.dbQueue.read { db in
            let pItems = try PinboardItem
                .filter(Column("pinboard_id") == pinboard.id)
                .order(Column("sort_order").asc)
                .fetchAll(db)

            let clipIds = pItems.map(\.clipId)
            let clips = try ClipItem
                .filter(clipIds.contains(Column("id")))
                .fetchAll(db)

            return (clips, pItems)
        }
    }

    // MARK: - Private: Package

    private static func packageExport(
        pinboard: Pinboard,
        clipItems: [ClipItem],
        pinboardItems: [PinboardItem],
        to destinationURL: URL,
        imageStorage: ImageStorage
    ) async throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("bufr_export_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // Build junction lookup
        let junctionLookup = Dictionary(
            pinboardItems.map { ($0.clipId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Build exported items
        let exportedItems: [ExportedClipItem] = clipItems.compactMap { clip in
            guard let junction = junctionLookup[clip.id] else { return nil }
            return ExportedClipItem(
                clipItem: clip,
                sortOrder: junction.sortOrder,
                addedAt: junction.addedAt
            )
        }

        let export = PinboardExport(
            version: currentVersion,
            exportDate: Date(),
            pinboard: pinboard,
            items: exportedItems
        )

        // Write JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(export)
        try jsonData.write(to: tempDir.appendingPathComponent("pinboard.json"))

        // Copy images
        let imagesDir = tempDir.appendingPathComponent("images")
        try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        for clip in clipItems {
            guard let imagePath = clip.imagePath, !imagePath.isEmpty else { continue }
            if let data = await imageStorage.loadImageData(filename: imagePath) {
                try data.write(to: imagesDir.appendingPathComponent(imagePath))
            }
        }

        // Create ZIP via ditto
        try runDitto(arguments: ["-c", "-k", "--sequesterRsrc", tempDir.path, destinationURL.path])
    }

    // MARK: - Private: Unpackage

    @MainActor
    private static func unpackageImport(
        from fileURL: URL,
        database: AppDatabase,
        pinboardStore: PinboardStore,
        imageStorage: ImageStorage
    ) async throws -> Pinboard {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("bufr_import_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // Extract ZIP
        try runDitto(arguments: ["-x", "-k", fileURL.path, tempDir.path])

        // Read JSON
        let jsonURL = tempDir.appendingPathComponent("pinboard.json")
        guard fm.fileExists(atPath: jsonURL.path) else {
            throw PinboardExportError.invalidArchive
        }

        let jsonData = try Data(contentsOf: jsonURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let export: PinboardExport
        do {
            export = try decoder.decode(PinboardExport.self, from: jsonData)
        } catch {
            throw PinboardExportError.jsonDecodingFailed(error)
        }

        guard export.version <= currentVersion else {
            throw PinboardExportError.unsupportedVersion(export.version)
        }

        // Create new pinboard
        let newBoard = try pinboardStore.create(
            name: export.pinboard.name,
            icon: export.pinboard.icon,
            color: export.pinboard.color
        )

        // Import items
        let imagesImportDir = tempDir.appendingPathComponent("images")

        for exportedItem in export.items {
            let clip = exportedItem.clipItem

            // Check dedup by hash
            let existingClip = try findClipByHash(clip.hash, database: database)

            let clipIdToUse: UUID

            if let existing = existingClip {
                clipIdToUse = existing.id
            } else {
                // Import image if present
                let clipToInsert: ClipItem
                if let imagePath = clip.imagePath, !imagePath.isEmpty,
                   fm.fileExists(atPath: imagesImportDir.appendingPathComponent(imagePath).path) {
                    let imageData = try Data(contentsOf: imagesImportDir.appendingPathComponent(imagePath))
                    let savedFilename = try await imageStorage.saveImage(imageData, id: clip.id)
                    clipToInsert = ClipItem(
                        id: clip.id,
                        contentType: clip.contentType,
                        textContent: clip.textContent,
                        richContent: clip.richContent,
                        imagePath: savedFilename,
                        filePaths: clip.filePaths,
                        sourceAppId: clip.sourceAppId,
                        sourceAppName: clip.sourceAppName,
                        createdAt: clip.createdAt,
                        isPinned: clip.isPinned,
                        isFavorite: clip.isFavorite,
                        hash: clip.hash,
                        customTitle: clip.customTitle
                    )
                } else {
                    clipToInsert = clip
                }

                try insertClip(clipToInsert, database: database)
                clipIdToUse = clipToInsert.id
            }

            // Add junction
            try insertJunction(
                pinboardId: newBoard.id,
                clipId: clipIdToUse,
                sortOrder: exportedItem.sortOrder,
                addedAt: exportedItem.addedAt,
                database: database
            )
        }

        try pinboardStore.fetchPinboards()
        return newBoard
    }

    // MARK: - Private: DB helpers

    private static func findClipByHash(_ hash: String, database: AppDatabase) throws -> ClipItem? {
        try database.dbQueue.read { db in
            try ClipItem
                .filter(ClipItem.Columns.hash == hash)
                .fetchOne(db)
        }
    }

    private static func insertClip(_ clip: ClipItem, database: AppDatabase) throws {
        let clipCopy = clip
        try database.dbQueue.write { db in
            try clipCopy.insert(db)
        }
    }

    private static func insertJunction(
        pinboardId: UUID,
        clipId: UUID,
        sortOrder: Int,
        addedAt: Date,
        database: AppDatabase
    ) throws {
        let junction = PinboardItem(
            pinboardId: pinboardId,
            clipId: clipId,
            sortOrder: sortOrder,
            addedAt: addedAt
        )
        try database.dbQueue.write { db in
            try junction.insert(db)
        }
    }

    // MARK: - Private: Export directory

    private static func exportDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Bufr")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Private: Modal panel helper

    @MainActor
    private static func runModalPanel(_ panel: NSSavePanel) -> NSApplication.ModalResponse {
        NSApp.activate()
        // Suspend click-outside monitoring so the save/open panel isn't dismissed
        let floatingPanel = NSApp.windows.compactMap { $0 as? FloatingPanel }.first
        floatingPanel?.suspendClickMonitoring()
        let response = panel.runModal()
        floatingPanel?.resumeClickMonitoring()
        return response
    }

    // MARK: - Private: ditto

    private static func runDitto(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            if arguments.contains("-c") {
                throw PinboardExportError.zipCreationFailed(errorMsg)
            } else {
                throw PinboardExportError.zipExtractionFailed(errorMsg)
            }
        }
    }
}
