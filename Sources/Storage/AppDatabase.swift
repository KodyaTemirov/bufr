import Foundation
import GRDB

final class AppDatabase: Sendable {
    let dbQueue: DatabaseQueue

    /// Production initializer — creates DB file in Application Support
    static let shared: AppDatabase = {
        let folderURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clipo", isDirectory: true)

        try! FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )

        let dbURL = folderURL.appendingPathComponent("clipo.sqlite")
        let dbQueue = try! DatabaseQueue(path: dbURL.path)
        return AppDatabase(dbQueue: dbQueue)
    }()

    /// Testable initializer — accepts any DatabaseQueue (including in-memory)
    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
        try! Self.migrator.migrate(dbQueue)
    }

    /// Creates an in-memory database for testing
    static func makeEmpty() throws -> AppDatabase {
        AppDatabase(dbQueue: try DatabaseQueue())
    }

    // MARK: - Migrations

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_createClipItems") { db in
            try db.create(table: "clip_items") { t in
                t.column("id", .text).primaryKey()
                t.column("content_type", .text).notNull()
                t.column("text_content", .text)
                t.column("rich_content", .blob)
                t.column("image_path", .text)
                t.column("file_paths", .text)
                t.column("source_app_id", .text)
                t.column("source_app_name", .text)
                t.column("created_at", .datetime).notNull()
                t.column("is_pinned", .boolean).notNull().defaults(to: false)
                t.column("is_favorite", .boolean).notNull().defaults(to: false)
                t.column("hash", .text).notNull()
            }

            try db.create(index: "idx_clip_items_created_at", on: "clip_items", columns: ["created_at"])
            try db.create(index: "idx_clip_items_hash", on: "clip_items", columns: ["hash"])
            try db.create(index: "idx_clip_items_content_type", on: "clip_items", columns: ["content_type"])

            // FTS5 full-text search
            try db.create(virtualTable: "clip_items_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clip_items")
                t.tokenizer = .unicode61()
                t.column("text_content")
                t.column("source_app_name")
            }
        }

        migrator.registerMigration("v1_createExcludedApps") { db in
            try db.create(table: "excluded_apps") { t in
                t.column("bundle_id", .text).primaryKey()
                t.column("app_name", .text).notNull()
            }

            // Pre-populate with common password managers
            try db.execute(sql: """
                INSERT INTO excluded_apps (bundle_id, app_name) VALUES
                ('com.agilebits.onepassword7', '1Password 7'),
                ('com.1password.1password', '1Password'),
                ('com.apple.keychainaccess', 'Keychain Access')
            """)
        }

        migrator.registerMigration("v1_createPinboards") { db in
            try db.create(table: "pinboards") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("icon", .text)
                t.column("color", .text)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .datetime).notNull()
            }

            try db.create(table: "pinboard_items") { t in
                t.column("pinboard_id", .text)
                    .notNull()
                    .references("pinboards", onDelete: .cascade)
                t.column("clip_id", .text)
                    .notNull()
                    .references("clip_items", onDelete: .cascade)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("added_at", .datetime).notNull()
                t.primaryKey(["pinboard_id", "clip_id"])
            }
        }

        return migrator
    }
}
