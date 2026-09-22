# Bufr 3.0 — M0 «Фундамент»: план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Подготовить кодовую базу Bufr к скриншотам. После этапа приложение ведёт себя для пользователя так же, как раньше, но:
- есть тестовый таргет;
- схема БД готова к скриншотам и OCR;
- вся запись в историю идёт через единый `ClipIngestor`;
- Bufr не ловит собственные записи в буфер;
- горячие клавиши поддерживают несколько действий;
- настройки открываются через собственный `SettingsWindowController`.

**Architecture:** Слоистая архитектура не меняется: Models → Storage → Core → Views, центральный `AppState`. Новые единицы — `ClipIngestor` (единственный путь записи в `clip_items`), `PasteboardWriter` (единственный путь записи в `NSPasteboard` с маркером `com.bufr.app.self-write`), `HotKeyBindingStore` (JSON в UserDefaults) и `AppActivation` (переключение `.regular`/`.accessory` для обычных окон).

**Tech Stack:** Swift 6.2 tools (strict concurrency), SwiftUI + AppKit, GRDB 6 (SQLite + FTS5), soffes/HotKey, Swift Testing, macOS 26.

**Spec:** [docs/superpowers/specs/2026-09-23-screenshots-design.md](../specs/2026-09-23-screenshots-design.md). Этот план — первый из шести (M0–M5). План следующего этапа пишется, когда предыдущий этап слит.

**Отклонения от спецификации (осознанные):**
- `SystemShortcutInspector`, `PermissionsManager`, `AppRelauncher` и переменная подписи `BUFR_SIGN_IDENTITY` в `build-app.sh` переезжают в M1. Их первый потребитель — захват; в M0 их некому вызывать.
- Из API `ClipItemStore` в M0 входят только `existingItem(hash:)`, `insert(_:deduplicate:)` и `touch(_:)`. Остальное (`fetchItems(origin:)`, `search(query:origin:)`, `update`, `item(id:)`, `ocrText(for:)`) добавляется в тех этапах, где появляются его вызовы.
- `ImageEncoder` лежит в `Sources/Utilities/`, а не в `Screenshots/`: он нужен уже в M0 для конвертации TIFF → PNG при загрузке.
- `ImageStorage.replaceImage`/`invalidateThumbnail` переносятся в M4 (редактор).

## Global Constraints

- Платформа: `.macOS(.v26)` в `Package.swift`; `LSMinimumSystemVersion` в `SupportFiles/Info.plist` = `26.0`.
- Swift 6 strict concurrency: сборка без ошибок. Новые предупреждения допустимы только о deprecated API, которые уже используются в проекте (`activate(ignoringOtherApps:)`).
- Стиль: сервисы — `@MainActor @Observable final class`, хранилища файлов — `actor`, stateless-хелперы — `enum`/`struct` со `static func`. Логирование через `Logger(subsystem: "com.bufr.app", category: "<Type>")`, ошибки с `privacy: .public`. Разделы через `// MARK: -`. Комментарии в коде на английском.
- UI-строки только через `L10n("key")`. Каждый новый ключ добавляется во **все три** файла `Sources/Resources/{en,ru,uz}.lproj/Localizable.strings`.
- Новые поля `ClipItem` — только `Optional` с дефолтом `nil`: Codable `ClipItem` одновременно служит форматом экспорта `.bufr`.
- Схема БД в этом релизе меняется **одной** миграцией `v4_screenshotsAndOCR`. В DEBUG `eraseDatabaseOnSchemaChange = true` стирает БД разработчика при любой правке уже применённой миграции.
- Имена файлов картинок: `<uuid>.png` в `…/Bufr/images/`, миниатюры `<uuid>_thumb.png` в `…/Bufr/thumbnails/`. UUID файла == `ClipItem.id` для всех новых записей.
- Коммиты: сообщение на русском с префиксом `feat:` / `fix:` / `refactor:` / `test:`, последняя строка `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. В `git add` перечислять конкретные файлы: в корне лежат неотслеживаемые `Bufr.app.zip` и `bufr.png`, коммитить их нельзя.
- Проверки после каждой задачи: `swift build` и `swift test` из корня репозитория.

## Review Focus

Пять ситуаций, которые спецификация подразумевает и которые скорее всего ударят по реальному пользователю. У каждой есть тест в задаче-владельце:

1. **Старые картинки в истории, где в `.png` лежит TIFF.** Вставка из истории должна класть в буфер настоящий PNG. Тест `writeImageNormalizesLegacyTIFFBytes` (Task 5).
2. **Одна и та же картинка скопирована дважды почти одновременно** (два тика монитора или скриншот + копирование). Ожидается одна карточка, один файл, без сирот. Тест `concurrentDuplicatesLeaveOneItemAndOneFile` (Task 4).
3. **Пользователь с нестандартным хоткеем из версии 2.x** (сырые `NSEvent`-флаги с device-dependent битами). После обновления хоткей должен работать так же. Тест `legacyBindingIsMigratedWithDeviceBitsStripped` (Task 6).
4. **Пароли из менеджеров паролей** (`org.nspasteboard.ConcealedType`) по-прежнему не попадают в историю после рефакторинга монитора. Тест `ignoresConcealedContent` (Task 4).
5. **Обновление с существующей БД.** Старые строки (`origin = NULL`) видны и находятся поиском, а новый `ocr_text` участвует в FTS. Тест `v4KeepsLegacyRowsSearchable` (Task 1).

---

## Карта файлов

| Файл | Действие | Ответственность |
|---|---|---|
| `Package.swift` | M | + `.testTarget(BufrTests)` |
| `SupportFiles/Info.plist` | M | `LSMinimumSystemVersion` 26.0 |
| `Sources/Models/ClipOrigin.swift` | N | Откуда пришла запись: clipboard / screenshot / textCapture |
| `Sources/Models/ClipItem.swift` | M | + 6 optional-полей, `withoutLocalPaths()` |
| `Sources/Storage/AppDatabase.swift` | M | Миграция v4; `migrator` становится internal; путь через `AppPaths` |
| `Sources/Core/PinboardExportService.swift` | M | Переносит новые поля при импорте, выбрасывает локальные пути |
| `Sources/Storage/ClipItemStore.swift` | M | `existingItem(hash:)`, `insert(_:deduplicate:)`, `touch(_:)`; очистка через `deleteAssets` |
| `Sources/Storage/AppPaths.swift` | N | `~/Library/Application Support/Bufr` |
| `Sources/Storage/ImageStorage.swift` | M | `init(baseDirectory:)`, `deleteAssets(imagePath:itemId:)` вместо `deleteImage` |
| `Sources/Utilities/ImageEncoder.swift` | N | Любые байты ImageIO → PNG + размер в пикселях |
| `Sources/Core/ClipIngestor.swift` | N | Единый путь записи картинок и контента в историю |
| `Sources/Core/ClipboardMonitor.swift` | M | Пишет через `ClipIngestor`; пропускает маркер собственных записей |
| `Sources/Core/PasteboardWriter.swift` | N | Запись в pasteboard с маркером; PNG сразу, TIFF лениво |
| `Sources/Core/ClipboardPaster.swift` | M | Пишет через `PasteboardWriter` |
| `Sources/Models/HotKeyAction.swift` | N | Перечень действий с хоткеями (в M0 — только `togglePanel`) |
| `Sources/Models/HotKeyBinding.swift` | N | Сочетание в Carbon-кодах + отображение |
| `Sources/Storage/HotKeyBindingStore.swift` | N | JSON в UserDefaults, миграция старых ключей |
| `Sources/Core/HotKeyManager.swift` | M (переписан) | `[HotKeyAction: HotKey]`, `onAction`, suspend/resume |
| `Sources/Views/Common/HotKeyRecorderView.swift` | N | Кнопка-рекордер сочетания |
| `Sources/Views/Settings/HotKeySettingsView.swift` | M (переписан) | Список действий с рекордерами |
| `Sources/App/AppActivation.swift` | N | `.regular` пока открыты обычные окна |
| `Sources/Views/Settings/SettingsWindowController.swift` | N | Окно настроек с выбором вкладки из кода |
| `Sources/Views/Settings/SettingsView.swift` | M | `SettingsTab` становится internal, вкладка задаётся снаружи |
| `Sources/App/AppState.swift` | M | `clipIngestor`, `copyItem`, `bringToTop`, `perform(_:)` |
| `Sources/App/BufrApp.swift` | M | Удалена сцена `Settings` |
| `Sources/Views/MenuBar/MenuBarView.swift` | M | Копирование через AppState, хоткей из привязки, настройки через контроллер |
| `Sources/Views/PanelWindow/ClipPanelView.swift` | M | Кнопка настроек через контроллер |
| `Sources/Views/PanelWindow/ClipCardView.swift` | M | «Копировать» через `appState.copyItem` |
| `Sources/Resources/{en,ru,uz}.lproj/Localizable.strings` | M | Ключи хоткеев и заголовка окна настроек |
| `Tests/BufrTests/Support/TestSupport.swift` | N | Временные папки, тестовые PNG/TIFF |
| `Tests/BufrTests/*.swift` | N | Тесты задач |

---

### Task 1: Тестовый таргет, `ClipOrigin`, новые поля `ClipItem`, миграция v4

**Files:**
- Modify: `Package.swift`
- Modify: `SupportFiles/Info.plist:21-22`
- Create: `Sources/Models/ClipOrigin.swift`
- Modify: `Sources/Models/ClipItem.swift`
- Modify: `Sources/Storage/AppDatabase.swift`
- Modify: `Sources/Core/PinboardExportService.swift:257-276`, `:471-490`
- Test: `Tests/BufrTests/DatabaseMigrationTests.swift`, `Tests/BufrTests/ExportCompatibilityTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `enum ClipOrigin: String, Codable, Sendable, DatabaseValueConvertible { case clipboard, screenshot, textCapture = "text_capture" }`
  - поля `ClipItem`: `origin: ClipOrigin?`, `ocrText: String?`, `annotationPath: String?`, `savedFilePath: String?`, `pixelWidth: Int?`, `pixelHeight: Int?` (параметры `init` с дефолтом `nil`, идут после `customTitle`)
  - `ClipItem.withoutLocalPaths() -> ClipItem`
  - `AppDatabase.migrator` (internal static)

- [ ] **Step 1: Добавить тестовый таргет и поднять минимальную версию macOS**

В `Package.swift` после `.executableTarget(...)` добавить второй таргет. Итоговый массив `targets`:

```swift
    targets: [
        .executableTarget(
            name: "Bufr",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "HotKey", package: "HotKey"),
            ],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "BufrTests",
            dependencies: ["Bufr"],
            path: "Tests/BufrTests"
        ),
    ]
```

В `SupportFiles/Info.plist` заменить

```xml
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
```

на

```xml
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
```

- [ ] **Step 2: Написать падающие тесты миграции**

Create `Tests/BufrTests/DatabaseMigrationTests.swift`:

```swift
import Foundation
import GRDB
import Testing
@testable import Bufr

@MainActor
struct DatabaseMigrationTests {
    @Test func v4KeepsLegacyRowsSearchable() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v3_pinboardItemsIndexes")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO clip_items (id, content_type, text_content, created_at, is_pinned, is_favorite, hash)
                VALUES ('11111111-1111-1111-1111-111111111111', 'text', 'legacy hello',
                        '2026-01-01 00:00:00.000', 0, 0, 'h-legacy')
                """)
        }

        let database = try AppDatabase(dbQueue: queue) // applies v4
        let store = ClipItemStore(database: database)

        let found = try store.search(query: "legacy")
        #expect(found.count == 1)
        #expect(found.first?.origin == nil)
        #expect(found.first?.ocrText == nil)
    }

    @Test func ocrTextIsFullTextSearchable() throws {
        let store = ClipItemStore(database: try AppDatabase.makeEmpty())
        try store.insert(ClipItem(
            contentType: .image, imagePath: "a.png", hash: "h-ocr",
            origin: .screenshot, ocrText: "Привет мир"
        ))

        #expect(try store.search(query: "прив").count == 1)
    }

    @Test func newFieldsRoundTripThroughDatabase() throws {
        let database = try AppDatabase.makeEmpty()
        let item = ClipItem(
            contentType: .image, imagePath: "b.png", hash: "h-fields",
            origin: .screenshot, ocrText: "", annotationPath: "b.annotations.json",
            savedFilePath: "/Users/me/Pictures/Bufr/shot.png", pixelWidth: 2880, pixelHeight: 1800
        )
        try database.dbQueue.write { db in try item.insert(db) }

        let loaded = try database.dbQueue.read { db in
            try ClipItem.filter(ClipItem.Columns.hash == "h-fields").fetchOne(db)
        }
        #expect(loaded == item)
    }
}
```

- [ ] **Step 3: Написать падающие тесты совместимости экспорта**

Create `Tests/BufrTests/ExportCompatibilityTests.swift`:

```swift
import Foundation
import Testing
@testable import Bufr

struct ExportCompatibilityTests {
    /// A pinboard item exported by Bufr 2.x: none of the 3.0 keys are present.
    private let legacyJSON = """
    {"clip_item":{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","content_type":"text",
     "text_content":"hello","created_at":"2026-01-01T10:00:00Z","is_pinned":false,
     "is_favorite":false,"hash":"abc"},
     "sort_order":0,"added_at":"2026-01-01T10:00:00Z"}
    """

    @Test func legacyExportStillDecodes() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(ExportedClipItem.self, from: Data(legacyJSON.utf8))

        #expect(exported.clipItem.textContent == "hello")
        #expect(exported.clipItem.origin == nil)
        #expect(exported.clipItem.ocrText == nil)
    }

    @Test func withoutLocalPathsDropsMachineSpecificPaths() {
        let item = ClipItem(
            contentType: .image, imagePath: "c.png", hash: "h",
            origin: .screenshot, ocrText: "text", annotationPath: "c.annotations.json",
            savedFilePath: "/Users/me/Pictures/Bufr/c.png", pixelWidth: 10, pixelHeight: 20
        )
        let portable = item.withoutLocalPaths()

        #expect(portable.annotationPath == nil)
        #expect(portable.savedFilePath == nil)
        #expect(portable.origin == .screenshot)
        #expect(portable.ocrText == "text")
        #expect(portable.pixelWidth == 10)
    }
}
```

- [ ] **Step 4: Убедиться, что тесты не компилируются**

Run: `swift test`
Expected: FAIL — ошибка компиляции `extra arguments at positions … in call` / `value of type 'ClipItem' has no member 'origin'` и `'migrator' is inaccessible due to 'private' protection level`.

- [ ] **Step 5: Создать `ClipOrigin`**

Create `Sources/Models/ClipOrigin.swift`:

```swift
import Foundation
import GRDB

/// Where a history item came from. `nil` in the database means a row created before Bufr 3.0
/// (always clipboard).
enum ClipOrigin: String, Codable, Sendable, DatabaseValueConvertible {
    case clipboard
    case screenshot
    case textCapture = "text_capture"
}
```

- [ ] **Step 6: Добавить поля в `ClipItem`**

В `Sources/Models/ClipItem.swift`:

1. После `var customTitle: String?` добавить:

```swift
    var origin: ClipOrigin?
    var ocrText: String?          // nil = not recognized yet, "" = recognized, no text
    var annotationPath: String?   // "<uuid>.annotations.json" (editor layers)
    var savedFilePath: String?    // absolute path of the copy in the user's screenshot folder
    var pixelWidth: Int?
    var pixelHeight: Int?
```

2. В `init` после параметра `customTitle: String? = nil` добавить параметры и присваивания:

```swift
        customTitle: String? = nil,
        origin: ClipOrigin? = nil,
        ocrText: String? = nil,
        annotationPath: String? = nil,
        savedFilePath: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) {
```

и в конце тела `init`:

```swift
        self.origin = origin
        self.ocrText = ocrText
        self.annotationPath = annotationPath
        self.savedFilePath = savedFilePath
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
```

3. После `displayTitle` (внутри основного `struct ClipItem`) добавить:

```swift
    /// Copy suitable for another machine: drops paths that only make sense locally.
    func withoutLocalPaths() -> ClipItem {
        var copy = self
        copy.annotationPath = nil
        copy.savedFilePath = nil
        return copy
    }
```

4. В **оба** enum `Columns` и `CodingKeys` после `case customTitle = "custom_title"` добавить:

```swift
        case origin
        case ocrText = "ocr_text"
        case annotationPath = "annotation_path"
        case savedFilePath = "saved_file_path"
        case pixelWidth = "pixel_width"
        case pixelHeight = "pixel_height"
```

- [ ] **Step 7: Добавить миграцию v4 и открыть `migrator` для тестов**

В `Sources/Storage/AppDatabase.swift`:

1. Заменить `private static var migrator: DatabaseMigrator {` на `static var migrator: DatabaseMigrator {` и добавить над ним комментарий `/// Internal so tests can migrate a database step by step.`
2. После `migrator.registerMigration("v3_pinboardItemsIndexes") { … }` и перед `return migrator` вставить:

```swift
        migrator.registerMigration("v4_screenshotsAndOCR") { db in
            try db.alter(table: "clip_items") { t in
                t.add(column: "origin", .text)            // NULL = pre-3.0 clipboard row
                t.add(column: "ocr_text", .text)          // NULL = pending, "" = no text
                t.add(column: "annotation_path", .text)
                t.add(column: "saved_file_path", .text)
                t.add(column: "pixel_width", .integer)
                t.add(column: "pixel_height", .integer)
            }

            try db.create(
                index: "idx_clip_items_origin_created_at",
                on: "clip_items",
                columns: ["origin", "created_at"]
            )
            // Lets the OCR indexer find pending images without a table scan
            try db.execute(sql: """
                CREATE INDEX idx_clip_items_ocr_pending ON clip_items(created_at)
                WHERE content_type = 'image' AND ocr_text IS NULL
                """)

            // Rebuild FTS5 with ocr_text (same procedure as v2_addCustomTitle)
            try db.execute(sql: "DROP TRIGGER IF EXISTS __clip_items_fts_ai")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __clip_items_fts_ad")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __clip_items_fts_au")
            try db.drop(table: "clip_items_fts")

            try db.create(virtualTable: "clip_items_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clip_items")
                t.tokenizer = .unicode61()
                t.column("text_content")
                t.column("source_app_name")
                t.column("custom_title")
                t.column("ocr_text")
            }
        }
```

- [ ] **Step 8: Переносить новые поля при импорте досок**

В `Sources/Core/PinboardExportService.swift` оба явных вызова `ClipItem(` (около строк 260 и 474) дополнить после `customTitle: clip.customTitle`:

```swift
                        customTitle: clip.customTitle,
                        origin: clip.origin,
                        ocrText: clip.ocrText,
                        pixelWidth: clip.pixelWidth,
                        pixelHeight: clip.pixelHeight
                    )
```

и в обеих ветках `} else { clipToInsert = clip }` заменить `clipToInsert = clip` на:

```swift
                    clipToInsert = clip.withoutLocalPaths()
```

- [ ] **Step 9: Запустить тесты**

Run: `swift test`
Expected: PASS — `DatabaseMigrationTests` (3) и `ExportCompatibilityTests` (2).

- [ ] **Step 10: Проверить, что приложение собирается**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 11: Commit**

```bash
git add Package.swift SupportFiles/Info.plist Sources/Models/ClipOrigin.swift Sources/Models/ClipItem.swift \
  Sources/Storage/AppDatabase.swift Sources/Core/PinboardExportService.swift \
  Tests/BufrTests/DatabaseMigrationTests.swift Tests/BufrTests/ExportCompatibilityTests.swift
git commit -m "$(cat <<'EOF'
feat: схема БД v4 для скриншотов и OCR, тестовый таргет

Новые поля ClipItem (origin, ocr_text, annotation_path, saved_file_path,
pixel_width/height), FTS5 теперь индексирует ocr_text. Импорт досок
переносит новые поля и не тащит локальные пути.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: API `ClipItemStore` для дедупликации и «поднять наверх»

**Files:**
- Modify: `Sources/Storage/ClipItemStore.swift:34-53`
- Test: `Tests/BufrTests/ClipItemStoreTests.swift`

**Interfaces:**
- Consumes: `ClipItem` (Task 1)
- Produces:
  - `func existingItem(hash: String) throws -> ClipItem?`
  - `@discardableResult func insert(_ item: ClipItem, deduplicate: Bool = true) throws -> ClipItem` (при `deduplicate == true` и совпадении хеша поднимает `createdAt` у существующей записи и возвращает её — прежнее поведение)
  - `@discardableResult func touch(_ item: ClipItem) throws -> ClipItem` (ставит `createdAt = now`, сохраняет, вызывает `prependItem`)

- [ ] **Step 1: Написать падающие тесты**

Create `Tests/BufrTests/ClipItemStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import Bufr

@MainActor
struct ClipItemStoreTests {
    let store: ClipItemStore

    init() throws {
        store = ClipItemStore(database: try AppDatabase.makeEmpty())
    }

    @Test func insertDeduplicatesByHashByDefault() throws {
        let first = try store.insert(ClipItem(contentType: .text, textContent: "a", hash: "same"))
        let second = try store.insert(ClipItem(contentType: .text, textContent: "a", hash: "same"))

        #expect(second.id == first.id)
        #expect(try store.existingItem(hash: "same")?.id == first.id)
    }

    @Test func insertWithoutDeduplicationKeepsBoth() throws {
        let first = try store.insert(ClipItem(contentType: .image, hash: "shot"), deduplicate: false)
        let second = try store.insert(ClipItem(contentType: .image, hash: "shot"), deduplicate: false)

        #expect(first.id != second.id)
        try store.fetchItems()
        #expect(store.items.count == 2)
    }

    @Test func existingItemReturnsNilForUnknownHash() throws {
        #expect(try store.existingItem(hash: "missing") == nil)
    }

    @Test func touchMovesItemToTopAndBumpsDate() throws {
        let old = try store.insert(ClipItem(
            contentType: .text, textContent: "old",
            createdAt: Date(timeIntervalSince1970: 0), hash: "h-old"
        ))
        let new = try store.insert(ClipItem(contentType: .text, textContent: "new", hash: "h-new"))
        try store.fetchItems()
        #expect(store.items.map(\.id) == [new.id, old.id])

        let touched = try store.touch(old)

        #expect(touched.createdAt > Date(timeIntervalSince1970: 0))
        #expect(store.items.map(\.id) == [old.id, new.id])
        try store.fetchItems()
        #expect(store.items.first?.id == old.id)
    }
}
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `swift test --filter ClipItemStoreTests`
Expected: FAIL — `extra argument 'deduplicate' in call`, `value of type 'ClipItemStore' has no member 'existingItem'`, `… 'touch'`.

- [ ] **Step 3: Реализовать**

В `Sources/Storage/ClipItemStore.swift` заменить весь раздел `// MARK: - Insert (with deduplication)` (текущий `insert(_:)`) на:

```swift
    // MARK: - Insert (with deduplication)

    func existingItem(hash: String) throws -> ClipItem? {
        try database.dbQueue.read { db in
            try ClipItem
                .filter(ClipItem.Columns.hash == hash)
                .fetchOne(db)
        }
    }

    /// Inserts `item`. With `deduplicate`, an item with the same hash is brought to the top
    /// (its `createdAt` is bumped) and returned instead of inserting a copy.
    @discardableResult
    func insert(_ item: ClipItem, deduplicate: Bool = true) throws -> ClipItem {
        try database.dbQueue.write { db in
            if deduplicate, var existing = try ClipItem
                .filter(ClipItem.Columns.hash == item.hash)
                .fetchOne(db) {
                existing.createdAt = Date()
                try existing.update(db)
                return existing
            }

            try item.insert(db)
            return item
        }
    }

    /// Moves an existing item to the top of the history.
    @discardableResult
    func touch(_ item: ClipItem) throws -> ClipItem {
        let touched = try database.dbQueue.write { db -> ClipItem in
            var updated = item
            updated.createdAt = Date()
            try updated.update(db)
            return updated
        }
        prependItem(touched)
        return touched
    }
```

- [ ] **Step 4: Запустить тесты**

Run: `swift test --filter ClipItemStoreTests`
Expected: PASS (4 теста).

- [ ] **Step 5: Commit**

```bash
git add Sources/Storage/ClipItemStore.swift Tests/BufrTests/ClipItemStoreTests.swift
git commit -m "$(cat <<'EOF'
feat: ClipItemStore — existingItem, insert(deduplicate:), touch

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `AppPaths`, внедряемый `ImageStorage`, `deleteAssets`, `ImageEncoder`

**Files:**
- Create: `Sources/Storage/AppPaths.swift`
- Modify: `Sources/Storage/ImageStorage.swift`
- Modify: `Sources/Storage/AppDatabase.swift:10-12`
- Modify: `Sources/Storage/ClipItemStore.swift:90-95`, `:122-127`
- Modify: `Sources/App/AppState.swift:231-238`
- Create: `Sources/Utilities/ImageEncoder.swift`
- Create: `Tests/BufrTests/Support/TestSupport.swift`
- Test: `Tests/BufrTests/ImageStorageTests.swift`, `Tests/BufrTests/ImageEncoderTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `enum AppPaths { static let support: URL }`
  - `ImageStorage.init(baseDirectory: URL)`; `static let shared = ImageStorage(baseDirectory: AppPaths.support)`
  - `func deleteAssets(imagePath: String?, itemId: UUID)` (actor-isolated, заменяет `deleteImage(filename:id:)`)
  - `nonisolated static func uuid(fromImagePath: String) -> UUID?`
  - `enum ImageEncoder { struct NormalizedImage: Sendable { let pngData: Data; let pixelWidth: Int; let pixelHeight: Int }; static func normalizedPNG(_ data: Data) -> NormalizedImage? }`
  - Тестовые хелперы: `TestSupport.makeTempDirectory() throws -> URL`; `TestImages.png(width:height:)`, `TestImages.tiff(width:height:)`, `TestImages.pngSignature`

- [ ] **Step 1: Создать тестовые хелперы**

Create `Tests/BufrTests/Support/TestSupport.swift`:

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TestSupport {
    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufrTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum TestImages {
    static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

    /// Solid red image; different sizes produce different bytes (useful for dedup tests).
    static func cgImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func encoded(_ type: UTType, width: Int, height: Int) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cgImage(width: width, height: height), nil)
        _ = CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func png(width: Int = 4, height: Int = 3) -> Data { encoded(.png, width: width, height: height) }
    static func tiff(width: Int = 4, height: Int = 3) -> Data { encoded(.tiff, width: width, height: height) }
}
```

- [ ] **Step 2: Написать падающие тесты**

Create `Tests/BufrTests/ImageEncoderTests.swift`:

```swift
import Foundation
import Testing
@testable import Bufr

struct ImageEncoderTests {
    @Test func pngPassesThroughUnchanged() throws {
        let png = TestImages.png(width: 5, height: 2)
        let result = try #require(ImageEncoder.normalizedPNG(png))

        #expect(result.pngData == png)
        #expect(result.pixelWidth == 5)
        #expect(result.pixelHeight == 2)
    }

    @Test func tiffIsConvertedToPNG() throws {
        let result = try #require(ImageEncoder.normalizedPNG(TestImages.tiff(width: 6, height: 4)))

        #expect(Array(result.pngData.prefix(4)) == TestImages.pngSignature)
        #expect(result.pixelWidth == 6)
        #expect(result.pixelHeight == 4)
    }

    @Test func garbageReturnsNil() {
        #expect(ImageEncoder.normalizedPNG(Data([0, 1, 2, 3])) == nil)
    }
}
```

Create `Tests/BufrTests/ImageStorageTests.swift`:

```swift
import Foundation
import Testing
@testable import Bufr

struct ImageStorageTests {
    @Test func saveImageUsesBaseDirectory() async throws {
        let dir = try TestSupport.makeTempDirectory()
        let storage = ImageStorage(baseDirectory: dir)
        let id = UUID()

        let filename = try await storage.saveImage(TestImages.png(), id: id)

        #expect(filename == "\(id.uuidString).png")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("images/\(filename)").path))
    }

    /// Pre-3.0 rows used one UUID for the file and another for the item.
    @Test func deleteAssetsRemovesImageAndThumbnailsForBothIds() async throws {
        let dir = try TestSupport.makeTempDirectory()
        let storage = ImageStorage(baseDirectory: dir)
        let fileId = UUID()
        let itemId = UUID()
        let images = dir.appendingPathComponent("images")
        let thumbnails = dir.appendingPathComponent("thumbnails")
        try TestImages.png().write(to: images.appendingPathComponent("\(fileId.uuidString).png"))
        for id in [fileId, itemId] {
            try Data([1]).write(to: thumbnails.appendingPathComponent("\(id.uuidString)_thumb.png"))
        }

        await storage.deleteAssets(imagePath: "\(fileId.uuidString).png", itemId: itemId)

        #expect(try FileManager.default.contentsOfDirectory(atPath: images.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: thumbnails.path).isEmpty)
    }

    @Test func deleteAssetsIgnoresPathTraversal() async throws {
        let dir = try TestSupport.makeTempDirectory()
        let storage = ImageStorage(baseDirectory: dir)
        let outside = dir.appendingPathComponent("keep.png")
        try Data([1]).write(to: outside)

        await storage.deleteAssets(imagePath: "../keep.png", itemId: UUID())

        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func uuidFromImagePath() {
        let id = UUID()
        #expect(ImageStorage.uuid(fromImagePath: "\(id.uuidString).png") == id)
        #expect(ImageStorage.uuid(fromImagePath: "not-a-uuid.png") == nil)
    }
}
```

- [ ] **Step 3: Убедиться, что тесты падают**

Run: `swift test --filter "ImageEncoderTests|ImageStorageTests"`
Expected: FAIL — `cannot find 'ImageEncoder' in scope`, `'ImageStorage' initializer is inaccessible due to 'private' protection level`, `no member 'deleteAssets'`.

- [ ] **Step 4: Создать `AppPaths`**

Create `Sources/Storage/AppPaths.swift`:

```swift
import Foundation

enum AppPaths {
    /// ~/Library/Application Support/Bufr
    static let support: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Bufr", isDirectory: true)
}
```

В `Sources/Storage/AppDatabase.swift` в `static let shared` заменить

```swift
            let folderURL = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Bufr", isDirectory: true)
```

на

```swift
            let folderURL = AppPaths.support
```

- [ ] **Step 5: Сделать `ImageStorage` внедряемым и добавить `deleteAssets`**

В `Sources/Storage/ImageStorage.swift`:

1. Заменить `static let shared = ImageStorage()` на `static let shared = ImageStorage(baseDirectory: AppPaths.support)`.
2. Заменить весь `private init() { … }` на:

```swift
    init(baseDirectory: URL) {
        imagesDir = baseDirectory.appendingPathComponent("images", isDirectory: true)
        thumbnailsDir = baseDirectory.appendingPathComponent("thumbnails", isDirectory: true)

        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
```

3. Заменить метод `deleteImage(filename:id:)` целиком на:

```swift
    /// Removes an item's image and thumbnail. Rows created before 3.0 used a different UUID
    /// for the file than for the item, so thumbnails for both UUIDs are removed.
    func deleteAssets(imagePath: String?, itemId: UUID) {
        var ids: Set<UUID> = [itemId]
        if let imagePath, isValidFilename(imagePath) {
            try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(imagePath))
            if let fileId = Self.uuid(fromImagePath: imagePath) {
                ids.insert(fileId)
            }
        }
        for id in ids {
            try? FileManager.default.removeItem(at: thumbnailsDir.appendingPathComponent("\(id.uuidString)_thumb.png"))
            thumbnailCache.removeObject(forKey: id.uuidString as NSString)
        }
    }

    /// "<uuid>.png" → uuid
    nonisolated static func uuid(fromImagePath imagePath: String) -> UUID? {
        UUID(uuidString: (imagePath as NSString).deletingPathExtension)
    }
```

- [ ] **Step 6: Перевести вызовы `deleteImage` на `deleteAssets`**

В `Sources/Storage/ClipItemStore.swift` в `deleteOlderThan(days:)` и `enforceHistoryLimit(_:)` заменить

```swift
                    await ImageStorage.shared.deleteImage(filename: path, id: id)
```

на

```swift
                    await ImageStorage.shared.deleteAssets(imagePath: path, itemId: id)
```

В `Sources/App/AppState.swift` в `deleteItem(_:)` заменить

```swift
                    await ImageStorage.shared.deleteImage(filename: imagePath, id: item.id)
```

на

```swift
                    await ImageStorage.shared.deleteAssets(imagePath: imagePath, itemId: item.id)
```

- [ ] **Step 7: Создать `ImageEncoder`**

Create `Sources/Utilities/ImageEncoder.swift`:

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageEncoder {
    struct NormalizedImage: Sendable {
        let pngData: Data
        let pixelWidth: Int
        let pixelHeight: Int
    }

    /// Returns PNG bytes plus pixel size for any ImageIO-readable data.
    /// PNG input is returned byte-for-byte; other formats (TIFF from the pasteboard) are
    /// re-encoded, keeping the DPI so Retina images keep their point size.
    static func normalizedPNG(_ data: Data) -> NormalizedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }

        if let type = CGImageSourceGetType(source) as String?, type == UTType.png.identifier {
            return NormalizedImage(pngData: data, pixelWidth: width, pixelHeight: height)
        }

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        var outputProperties: [CFString: Any] = [:]
        outputProperties[kCGImagePropertyDPIWidth] = properties[kCGImagePropertyDPIWidth]
        outputProperties[kCGImagePropertyDPIHeight] = properties[kCGImagePropertyDPIHeight]

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, outputProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return NormalizedImage(pngData: output as Data, pixelWidth: width, pixelHeight: height)
    }
}
```

- [ ] **Step 8: Запустить все тесты**

Run: `swift test`
Expected: PASS — все тесты, включая `ImageEncoderTests` (3) и `ImageStorageTests` (4).

- [ ] **Step 9: Commit**

```bash
git add Sources/Storage/AppPaths.swift Sources/Storage/ImageStorage.swift Sources/Storage/AppDatabase.swift \
  Sources/Storage/ClipItemStore.swift Sources/App/AppState.swift Sources/Utilities/ImageEncoder.swift \
  Tests/BufrTests/Support/TestSupport.swift Tests/BufrTests/ImageStorageTests.swift Tests/BufrTests/ImageEncoderTests.swift
git commit -m "$(cat <<'EOF'
fix: удаление картинок чистит миниатюры, ImageEncoder для TIFF → PNG

ImageStorage принимает базовую папку (для тестов), deleteAssets удаляет
миниатюры и по UUID файла, и по id записи — у старых записей они
различались, и миниатюры оставались сиротами.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `ClipIngestor` и перевод `ClipboardMonitor` на него

**Files:**
- Create: `Sources/Core/ClipIngestor.swift`
- Modify: `Sources/Core/ClipboardMonitor.swift` (переписать раздел `// MARK: - Private` и `init`)
- Modify: `Sources/App/AppState.swift` (сервисы и `init`)
- Test: `Tests/BufrTests/ClipIngestorTests.swift`, `Tests/BufrTests/ClipboardMonitorTests.swift`

**Interfaces:**
- Consumes: `ClipItemStore.existingItem(hash:)`, `insert(_:deduplicate:)`, `touch(_:)`, `prependItem(_:)` (Task 2); `ImageStorage.saveImage(_:id:)`, `deleteAssets(imagePath:itemId:)`, `ImageEncoder.normalizedPNG(_:)` (Task 3); `ClipOrigin` (Task 1)
- Produces:
  - `@MainActor final class ClipIngestor { init(store: ClipItemStore, imageStorage: ImageStorage = .shared) }`
  - `struct ClipIngestor.ImageInput: Sendable { var id = UUID(); var data: Data; var origin: ClipOrigin; var sourceAppId: String? = nil; var sourceAppName: String? = nil; var deduplicate = true }`
  - `struct ClipIngestor.ContentInput: Sendable { var contentType: ContentType; var textContent: String? = nil; var richContent: Data? = nil; var filePaths: [String]? = nil; var origin: ClipOrigin; var sourceAppId: String? = nil; var sourceAppName: String? = nil }`
  - `@discardableResult func ingestImage(_ input: ImageInput) async throws -> ClipItem`
  - `@discardableResult func ingestContent(_ input: ContentInput) throws -> ClipItem`
  - `enum ClipIngestor.IngestError: Error { case unreadableImage }`
  - `ClipboardMonitor.init(ingestor: ClipIngestor, exclusionManager: ExclusionManager, pasteboard: NSPasteboard = .general)`; `func checkForChanges()` становится internal
  - `AppState.clipIngestor: ClipIngestor`

- [ ] **Step 1: Написать падающие тесты ingestor**

Create `Tests/BufrTests/ClipIngestorTests.swift`:

```swift
import Foundation
import Testing
@testable import Bufr

@MainActor
struct ClipIngestorTests {
    let dir: URL
    let store: ClipItemStore
    let ingestor: ClipIngestor

    init() throws {
        dir = try TestSupport.makeTempDirectory()
        store = ClipItemStore(database: try AppDatabase.makeEmpty())
        ingestor = ClipIngestor(store: store, imageStorage: ImageStorage(baseDirectory: dir))
    }

    private func imageFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("images").path).sorted()
    }

    @Test func imageFileIsNamedAfterItemId() async throws {
        let item = try await ingestor.ingestImage(.init(data: TestImages.png(), origin: .clipboard))

        #expect(item.imagePath == "\(item.id.uuidString).png")
        #expect(try imageFiles() == ["\(item.id.uuidString).png"])
        #expect(item.origin == .clipboard)
        #expect(item.pixelWidth == 4)
        #expect(item.pixelHeight == 3)
        #expect(store.items.first?.id == item.id)
    }

    @Test func duplicateImageWritesNoSecondFile() async throws {
        let data = TestImages.png(width: 9, height: 9)
        let first = try await ingestor.ingestImage(.init(data: data, origin: .clipboard))
        let second = try await ingestor.ingestImage(.init(data: data, origin: .clipboard))

        #expect(second.id == first.id)
        #expect(try imageFiles().count == 1)
        #expect(store.items.count == 1)
    }

    @Test func concurrentDuplicatesLeaveOneItemAndOneFile() async throws {
        let data = TestImages.png(width: 7, height: 5)
        async let a = ingestor.ingestImage(.init(data: data, origin: .clipboard))
        async let b = ingestor.ingestImage(.init(data: data, origin: .clipboard))
        let (first, second) = try await (a, b)

        #expect(first.id == second.id)
        #expect(try imageFiles() == ["\(first.id.uuidString).png"])
        #expect(store.items.count == 1)
    }

    @Test func screenshotsSkipDeduplication() async throws {
        let data = TestImages.png(width: 8, height: 8)
        let first = try await ingestor.ingestImage(.init(data: data, origin: .screenshot, deduplicate: false))
        let second = try await ingestor.ingestImage(.init(data: data, origin: .screenshot, deduplicate: false))

        #expect(first.id != second.id)
        #expect(try imageFiles().count == 2)
    }

    @Test func tiffIsStoredAsRealPNGButHashedByOriginalBytes() async throws {
        let tiff = TestImages.tiff()
        let item = try await ingestor.ingestImage(.init(data: tiff, origin: .clipboard))

        let imagePath = try #require(item.imagePath)
        let stored = try Data(contentsOf: dir.appendingPathComponent("images/\(imagePath)"))
        #expect(Array(stored.prefix(4)) == TestImages.pngSignature)
        // Re-copying the same TIFF from another app must still deduplicate
        #expect(item.hash == HashGenerator.sha256(tiff))
    }

    @Test func unreadableImageThrowsAndWritesNothing() async throws {
        await #expect(throws: ClipIngestor.IngestError.self) {
            try await ingestor.ingestImage(.init(data: Data([0, 1, 2]), origin: .clipboard))
        }
        #expect(try imageFiles().isEmpty)
        #expect(store.items.isEmpty)
    }

    @Test func contentIsDeduplicatedAndPrepended() throws {
        let input = ClipIngestor.ContentInput(contentType: .text, textContent: "hello", origin: .clipboard)
        let first = try ingestor.ingestContent(input)
        let second = try ingestor.ingestContent(input)

        #expect(first.id == second.id)
        #expect(store.items.map(\.id) == [first.id])
        #expect(first.origin == .clipboard)
    }
}
```

- [ ] **Step 2: Написать падающие тесты монитора**

Create `Tests/BufrTests/ClipboardMonitorTests.swift`:

```swift
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
```

- [ ] **Step 3: Убедиться, что тесты падают**

Run: `swift test --filter "ClipIngestorTests|ClipboardMonitorTests"`
Expected: FAIL — `cannot find 'ClipIngestor' in scope`, `incorrect argument label in call (have 'ingestor:…', expected 'clipItemStore:…')`.

- [ ] **Step 4: Реализовать `ClipIngestor`**

Create `Sources/Core/ClipIngestor.swift`:

```swift
import Foundation

/// The single write path into history for clipboard content, screenshots and captured text.
/// Owns hashing, deduplication, PNG normalization and the file-name == item-id invariant.
@MainActor
final class ClipIngestor {
    struct ImageInput: Sendable {
        var id = UUID()
        var data: Data
        var origin: ClipOrigin
        var sourceAppId: String? = nil
        var sourceAppName: String? = nil
        var deduplicate = true
    }

    struct ContentInput: Sendable {
        var contentType: ContentType
        var textContent: String? = nil
        var richContent: Data? = nil
        var filePaths: [String]? = nil
        var origin: ClipOrigin
        var sourceAppId: String? = nil
        var sourceAppName: String? = nil
    }

    enum IngestError: Error {
        case unreadableImage
    }

    private let store: ClipItemStore
    private let imageStorage: ImageStorage

    init(store: ClipItemStore, imageStorage: ImageStorage = .shared) {
        self.store = store
        self.imageStorage = imageStorage
    }

    // MARK: - Images

    @discardableResult
    func ingestImage(_ input: ImageInput) async throws -> ClipItem {
        let data = input.data
        // Hash the original bytes so copying the same image again still deduplicates
        let hash = await Task.detached(priority: .userInitiated) {
            HashGenerator.sha256(data)
        }.value

        if input.deduplicate, let existing = try store.existingItem(hash: hash) {
            return try store.touch(existing)
        }

        guard let image = await Task.detached(priority: .userInitiated, operation: {
            ImageEncoder.normalizedPNG(data)
        }).value else {
            throw IngestError.unreadableImage
        }

        let filename = try await imageStorage.saveImage(image.pngData, id: input.id)
        let item = ClipItem(
            id: input.id,
            contentType: .image,
            imagePath: filename,
            sourceAppId: input.sourceAppId,
            sourceAppName: input.sourceAppName,
            hash: hash,
            origin: input.origin,
            pixelWidth: image.pixelWidth,
            pixelHeight: image.pixelHeight
        )

        let saved: ClipItem
        do {
            saved = try store.insert(item, deduplicate: input.deduplicate)
        } catch {
            await imageStorage.deleteAssets(imagePath: filename, itemId: item.id)
            throw error
        }

        if saved.id != item.id {
            // Another ingest stored the same content while this one was encoding
            await imageStorage.deleteAssets(imagePath: filename, itemId: item.id)
        }
        store.prependItem(saved)
        return saved
    }

    // MARK: - Text, rich text, URLs, colors, files

    @discardableResult
    func ingestContent(_ input: ContentInput) throws -> ClipItem {
        let hash = HashGenerator.hashForClipContent(
            type: input.contentType,
            text: input.textContent,
            imageData: nil,
            filePaths: input.filePaths
        )
        let item = ClipItem(
            contentType: input.contentType,
            textContent: input.textContent,
            richContent: input.richContent,
            filePaths: ClipItem.encodeFilePaths(input.filePaths ?? []),
            sourceAppId: input.sourceAppId,
            sourceAppName: input.sourceAppName,
            hash: hash,
            origin: input.origin
        )
        let saved = try store.insert(item)
        store.prependItem(saved)
        return saved
    }
}
```

- [ ] **Step 5: Перевести `ClipboardMonitor` на ingestor**

В `Sources/Core/ClipboardMonitor.swift`:

1. Заменить свойство `private let clipItemStore: ClipItemStore` на `private let ingestor: ClipIngestor`.
2. Заменить `init` на:

```swift
    init(
        ingestor: ClipIngestor,
        exclusionManager: ExclusionManager,
        pasteboard: NSPasteboard = .general
    ) {
        self.ingestor = ingestor
        self.exclusionManager = exclusionManager
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }
```

3. Заменить всё от `// MARK: - Private` до конца класса на:

```swift
    // MARK: - Change detection

    /// Internal (not private) so tests can drive it without the timer.
    func checkForChanges() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Check for concealed/sensitive content
        if ExclusionManager.containsConcealedContent(pasteboard) {
            return
        }

        // Check if source app is excluded
        let appBundleId = ExclusionManager.frontmostAppBundleId()
        if exclusionManager.isExcluded(bundleId: appBundleId) {
            return
        }
        let appName = ExclusionManager.frontmostAppName()

        let contentType = ContentTypeDetector.detect(from: pasteboard)

        if contentType == .image {
            // Oversized or unreadable images are skipped: a card without an image is useless
            guard let imageData = ContentTypeDetector.extractImageData(from: pasteboard),
                  imageData.count <= Self.maxImageSize else { return }
            let input = ClipIngestor.ImageInput(
                data: imageData, origin: .clipboard,
                sourceAppId: appBundleId, sourceAppName: appName
            )
            Task {
                do {
                    try await self.ingestor.ingestImage(input)
                    self.playSoundIfEnabled()
                } catch {
                    logger.error("Failed to save image clip: \(error.localizedDescription, privacy: .public)")
                }
            }
            return
        }

        let input = ClipIngestor.ContentInput(
            contentType: contentType,
            textContent: ContentTypeDetector.extractTextContent(from: pasteboard, type: contentType),
            richContent: ContentTypeDetector.extractRichContent(from: pasteboard),
            filePaths: ContentTypeDetector.extractFilePaths(from: pasteboard),
            origin: .clipboard,
            sourceAppId: appBundleId,
            sourceAppName: appName
        )

        // Skip empty content
        guard input.textContent != nil || input.filePaths != nil else { return }

        do {
            try ingestor.ingestContent(input)
            playSoundIfEnabled()
        } catch {
            logger.error("Failed to save clip item: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func playSoundIfEnabled() {
        if playCopySound {
            SoundManager.playCopySound()
        }
    }
}
```

- [ ] **Step 6: Подключить ingestor в `AppState`**

В `Sources/App/AppState.swift`:

1. В `// MARK: - Services` после `let clipItemStore: ClipItemStore` добавить `let clipIngestor: ClipIngestor`.
2. В `init` заменить

```swift
        self.clipItemStore = ClipItemStore(database: database)
        self.exclusionManager = ExclusionManager(database: database)
        self.clipboardMonitor = ClipboardMonitor(
            clipItemStore: clipItemStore,
            exclusionManager: exclusionManager
        )
```

на

```swift
        self.clipItemStore = ClipItemStore(database: database)
        self.clipIngestor = ClipIngestor(store: clipItemStore)
        self.exclusionManager = ExclusionManager(database: database)
        self.clipboardMonitor = ClipboardMonitor(
            ingestor: clipIngestor,
            exclusionManager: exclusionManager
        )
```

- [ ] **Step 7: Запустить все тесты**

Run: `swift test`
Expected: PASS — включая `ClipIngestorTests` (7) и `ClipboardMonitorTests` (3).

- [ ] **Step 8: Commit**

```bash
git add Sources/Core/ClipIngestor.swift Sources/Core/ClipboardMonitor.swift Sources/App/AppState.swift \
  Tests/BufrTests/ClipIngestorTests.swift Tests/BufrTests/ClipboardMonitorTests.swift
git commit -m "$(cat <<'EOF'
refactor: единый ClipIngestor для записи в историю

Файл картинки теперь называется по id записи, дубли не оставляют
файлов-сирот, TIFF из буфера сохраняется как настоящий PNG, у новых
записей проставляется origin и размер в пикселях.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `PasteboardWriter`, маркер собственных записей, копирование и вставка через него

**Files:**
- Create: `Sources/Core/PasteboardWriter.swift`
- Modify: `Sources/Core/ClipboardMonitor.swift` (ранний выход по маркеру)
- Modify: `Sources/Core/ClipboardPaster.swift` (переписать)
- Modify: `Sources/App/AppState.swift` (`pasteItem`, новые `copyItem`, `bringToTop`)
- Modify: `Sources/Views/PanelWindow/ClipCardView.swift:130-132`
- Modify: `Sources/Views/MenuBar/MenuBarView.swift:25-27`, `:77-84`
- Test: `Tests/BufrTests/PasteboardWriterTests.swift`, `Tests/BufrTests/ClipboardMonitorTests.swift`

**Interfaces:**
- Consumes: `ImageEncoder.normalizedPNG(_:)` (Task 3); `ClipboardMonitor.checkForChanges()` (Task 4); `ClipItemStore.touch(_:)` (Task 2)
- Produces:
  - `extension NSPasteboard.PasteboardType { static let bufrSelfWrite }` (`"com.bufr.app.self-write"`)
  - `@MainActor enum PasteboardWriter`:
    - `static func writeText(_ text: String, to pasteboard: NSPasteboard = .general)`
    - `static func writeImage(png: Data, to pasteboard: NSPasteboard = .general)`
    - `@discardableResult static func writeImage(anyImageData: Data, to pasteboard: NSPasteboard = .general) -> Bool`
    - `static func write(_ item: ClipItem, to pasteboard: NSPasteboard = .general)` — для всех типов, кроме `.image`
  - `AppState.copyItem(_ item: ClipItem)`

- [ ] **Step 1: Написать падающие тесты writer**

Create `Tests/BufrTests/PasteboardWriterTests.swift`:

```swift
import AppKit
import Testing
@testable import Bufr

@MainActor
struct PasteboardWriterTests {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.bufr.tests.\(UUID().uuidString)"))

    @Test func writeTextMarksSelfWrite() {
        PasteboardWriter.writeText("hello", to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "hello")
        #expect(pasteboard.types?.contains(.bufrSelfWrite) == true)
    }

    @Test func writeImageOffersPNGAndLazyTIFF() throws {
        PasteboardWriter.writeImage(png: TestImages.png(width: 3, height: 2), to: pasteboard)

        #expect(pasteboard.types?.contains(.png) == true)
        #expect(pasteboard.types?.contains(.bufrSelfWrite) == true)
        let tiff = try #require(pasteboard.data(forType: .tiff))
        #expect(NSBitmapImageRep(data: tiff)?.pixelsWide == 3)
    }

    /// History files written before 3.0 may contain TIFF bytes under a .png name.
    @Test func writeImageNormalizesLegacyTIFFBytes() throws {
        let written = PasteboardWriter.writeImage(anyImageData: TestImages.tiff(), to: pasteboard)

        #expect(written)
        let png = try #require(pasteboard.data(forType: .png))
        #expect(Array(png.prefix(4)) == TestImages.pngSignature)
    }

    @Test func writeImageRejectsGarbage() {
        #expect(PasteboardWriter.writeImage(anyImageData: Data([1, 2, 3]), to: pasteboard) == false)
    }

    @Test func writeFileItemKeepsURLsAndMarker() {
        let item = ClipItem(
            contentType: .file,
            filePaths: ClipItem.encodeFilePaths(["/tmp/bufr-test.txt"]),
            hash: "f"
        )

        PasteboardWriter.write(item, to: pasteboard)

        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        #expect(urls == [URL(fileURLWithPath: "/tmp/bufr-test.txt")])
        #expect(pasteboard.types?.contains(.bufrSelfWrite) == true)
    }

    @Test func writeRichTextKeepsPlainFallback() {
        let rtf = Data("{\\rtf1 hi}".utf8)
        let item = ClipItem(contentType: .richText, textContent: "hi", richContent: rtf, hash: "r")

        PasteboardWriter.write(item, to: pasteboard)

        #expect(pasteboard.data(forType: .rtf) == rtf)
        #expect(pasteboard.string(forType: .string) == "hi")
    }
}
```

Добавить в `Tests/BufrTests/ClipboardMonitorTests.swift` (внутрь `struct ClipboardMonitorTests`):

```swift
    @Test func ignoresBufrOwnWrites() {
        PasteboardWriter.writeText("written by bufr", to: pasteboard)

        monitor.checkForChanges()

        #expect(store.items.isEmpty)
    }
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `swift test --filter "PasteboardWriterTests|ClipboardMonitorTests"`
Expected: FAIL — `cannot find 'PasteboardWriter' in scope`, `type 'NSPasteboard.PasteboardType' has no member 'bufrSelfWrite'`.

- [ ] **Step 3: Реализовать `PasteboardWriter`**

Create `Sources/Core/PasteboardWriter.swift`:

```swift
import AppKit

extension NSPasteboard.PasteboardType {
    /// Marks pasteboard contents written by Bufr itself; ClipboardMonitor skips them
    /// because the item is already in history.
    static let bufrSelfWrite = NSPasteboard.PasteboardType("com.bufr.app.self-write")
}

/// The only place Bufr writes to a pasteboard. Every write carries the self-write marker.
@MainActor
enum PasteboardWriter {
    /// Keeps the lazy TIFF provider alive until the next image write.
    private static var tiffProvider: LazyTIFFProvider?

    static func writeText(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        markAsSelfWrite(pasteboard)
    }

    /// PNG is written up front; TIFF (for older apps) is produced only if someone asks for it,
    /// which avoids ~60 MB of TIFF for a 5K screenshot.
    static func writeImage(png: Data, to pasteboard: NSPasteboard = .general) {
        let provider = LazyTIFFProvider(pngData: png)
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setString("1", forType: .bufrSelfWrite)
        item.setDataProvider(provider, forTypes: [.tiff])
        tiffProvider = provider

        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    /// Accepts any ImageIO format (history files written before 3.0 may be TIFF).
    @discardableResult
    static func writeImage(anyImageData data: Data, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let png = ImageEncoder.normalizedPNG(data)?.pngData else { return false }
        writeImage(png: png, to: pasteboard)
        return true
    }

    /// Writes a non-image clip in its original format. Images go through `writeImage`.
    static func write(_ item: ClipItem, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()

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

        case .file:
            let urls = item.filePathsArray.map { URL(fileURLWithPath: $0) }
            pasteboard.writeObjects(urls as [NSURL])

        case .image:
            assertionFailure("Use writeImage(png:) for images")
        }

        markAsSelfWrite(pasteboard)
    }

    private static func markAsSelfWrite(_ pasteboard: NSPasteboard) {
        pasteboard.setString("1", forType: .bufrSelfWrite)
    }
}

private final class LazyTIFFProvider: NSObject, NSPasteboardItemDataProvider, Sendable {
    let pngData: Data

    init(pngData: Data) {
        self.pngData = pngData
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        guard type == .tiff, let tiff = NSBitmapImageRep(data: pngData)?.tiffRepresentation else { return }
        item.setData(tiff, forType: .tiff)
    }
}
```

- [ ] **Step 4: Монитор пропускает собственные записи**

В `Sources/Core/ClipboardMonitor.swift` в `checkForChanges()` сразу после `lastChangeCount = currentCount` вставить:

```swift

        // Bufr's own writes (paste from history, screenshots) are already in history
        if pasteboard.types?.contains(.bufrSelfWrite) == true {
            return
        }
```

- [ ] **Step 5: Запустить тесты writer и монитора**

Run: `swift test --filter "PasteboardWriterTests|ClipboardMonitorTests"`
Expected: PASS (6 + 4).

- [ ] **Step 6: Переписать `ClipboardPaster` поверх writer**

Заменить содержимое `Sources/Core/ClipboardPaster.swift` от начала файла до строки `/// Simulate Cmd+V keypress via CGEvent targeted to the frontmost app` на:

```swift
import AppKit

@MainActor
final class ClipboardPaster {

    /// Paste a clip item into the active application
    func paste(_ item: ClipItem, asPlainText: Bool = false) {
        Task {
            guard await write(item, asPlainText: asPlainText) else { return }
            try? await Task.sleep(for: .milliseconds(50))
            Self.simulatePaste()
        }
    }

    /// Copy item to clipboard without pasting
    func copyToClipboard(_ item: ClipItem, asPlainText: Bool = false) {
        Task {
            await write(item, asPlainText: asPlainText)
        }
    }

    // MARK: - Private

    /// Returns false when there was nothing to write (e.g. the image file is gone).
    @discardableResult
    private func write(_ item: ClipItem, asPlainText: Bool) async -> Bool {
        let pasteboard = NSPasteboard.general

        // Images ignore "plain text": pasting an empty string instead of the image helps nobody
        if item.contentType == .image {
            guard let imagePath = item.imagePath,
                  let data = await ImageStorage.shared.loadImageData(filename: imagePath)
            else { return false }
            return PasteboardWriter.writeImage(anyImageData: data, to: pasteboard)
        }

        if asPlainText {
            PasteboardWriter.writeText(item.textContent ?? "", to: pasteboard)
        } else {
            PasteboardWriter.write(item, to: pasteboard)
        }
        return true
    }

```

Метод `simulatePaste()` и закрывающая скобка класса остаются без изменений. Методы `schedulePaste()` и `writeOriginalFormat(_:to:)` удаляются: их заменили `Task.sleep` и `PasteboardWriter.write`.

- [ ] **Step 7: Поднимать вставленную/скопированную запись явно**

Монитор больше не ловит собственные записи Bufr, поэтому «поднять наверх» (раньше это делала повторная дедупликация) нужно вызывать явно.

В `Sources/App/AppState.swift` заменить раздел `// MARK: - Paste` целиком на:

```swift
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
```

В `Sources/Views/PanelWindow/ClipCardView.swift` заменить

```swift
            Button(L10n("card.copy")) {
                appState.clipboardPaster.copyToClipboard(item)
            }
```

на

```swift
            Button(L10n("card.copy")) {
                appState.copyItem(item)
            }
```

В `Sources/Views/MenuBar/MenuBarView.swift`:
1. В `ForEach` заменить `copyToClipboard(item)` на `AppState.shared.copyItem(item)`.
2. Удалить метод `private func copyToClipboard(_ item: ClipItem) { … }` целиком. Раньше он копировал только `textContent`, поэтому картинки из меню не копировались.

- [ ] **Step 8: Сборка и все тесты**

Run: `swift build && swift test`
Expected: `Build complete!`, все тесты PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/Core/PasteboardWriter.swift Sources/Core/ClipboardMonitor.swift Sources/Core/ClipboardPaster.swift \
  Sources/App/AppState.swift Sources/Views/PanelWindow/ClipCardView.swift Sources/Views/MenuBar/MenuBarView.swift \
  Tests/BufrTests/PasteboardWriterTests.swift Tests/BufrTests/ClipboardMonitorTests.swift
git commit -m "$(cat <<'EOF'
fix: вставка из истории больше не создаёт дубли

Все записи Bufr в буфер идут через PasteboardWriter с маркером
com.bufr.app.self-write, монитор их пропускает. Картинки кладутся как
PNG (TIFF — лениво), копирование картинок из меню строки меню работает.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Модель горячих клавиш — `HotKeyAction`, `HotKeyBinding`, `HotKeyBindingStore`

**Files:**
- Create: `Sources/Models/HotKeyAction.swift`
- Create: `Sources/Models/HotKeyBinding.swift`
- Create: `Sources/Storage/HotKeyBindingStore.swift`
- Test: `Tests/BufrTests/HotKeyBindingTests.swift`

**Interfaces:**
- Consumes: HotKey (`Key`, `KeyCombo(carbonKeyCode:carbonModifiers:)`, `NSEvent.ModifierFlags.carbonFlags`, `NSEvent.ModifierFlags(carbonFlags:)`)
- Produces:
  - `enum HotKeyAction: String, CaseIterable, Codable, Sendable { case togglePanel; var defaultBinding: HotKeyBinding?; var titleKey: String }`
  - `struct HotKeyBinding: Codable, Hashable, Sendable`:
    - `carbonKeyCode: UInt32`, `carbonModifiers: UInt32`
    - `init(carbonKeyCode:carbonModifiers:)`, `init(key: Key, modifiers: NSEvent.ModifierFlags)`
    - `static let relevantModifiers: NSEvent.ModifierFlags`
    - `var key: Key?`, `var modifiers: NSEvent.ModifierFlags`, `var keyCombo: KeyCombo`, `var displayString: String`
    - `static func modifierSymbols(_ modifiers: NSEvent.ModifierFlags) -> String`
    - `var keyboardShortcut: KeyboardShortcut?`
  - `struct HotKeyBindingStore`:
    - `static let storageKey = "hotKeys"`, `init(defaults: UserDefaults)`
    - `func binding(for: HotKeyAction) -> HotKeyBinding?`, `func save(_: HotKeyBinding?, for: HotKeyAction)`, `func reset(_: HotKeyAction)`
    - `func migrateLegacyIfNeeded()`

- [ ] **Step 1: Написать падающие тесты**

Create `Tests/BufrTests/HotKeyBindingTests.swift`:

```swift
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
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `swift test --filter HotKeyBindingTests`
Expected: FAIL — `cannot find 'HotKeyBindingStore' in scope`, `cannot find 'HotKeyBinding' in scope`.

- [ ] **Step 3: Реализовать `HotKeyAction`**

Create `Sources/Models/HotKeyAction.swift`:

```swift
import AppKit
import HotKey

/// Every global shortcut Bufr can register. Capture actions are added in M1.
enum HotKeyAction: String, CaseIterable, Codable, Sendable {
    case togglePanel

    var defaultBinding: HotKeyBinding? {
        switch self {
        case .togglePanel: HotKeyBinding(key: .v, modifiers: [.command, .shift])
        }
    }

    /// Localization key of the action's name in Settings
    var titleKey: String { "hotkeys.action.\(rawValue)" }
}
```

- [ ] **Step 4: Реализовать `HotKeyBinding`**

Create `Sources/Models/HotKeyBinding.swift`:

```swift
import AppKit
import HotKey
import SwiftUI

/// A global shortcut, stored as Carbon codes so it is independent of NSEvent flag noise.
struct HotKeyBinding: Codable, Hashable, Sendable {
    var carbonKeyCode: UInt32
    var carbonModifiers: UInt32

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(carbonKeyCode: UInt32, carbonModifiers: UInt32) {
        self.carbonKeyCode = carbonKeyCode
        self.carbonModifiers = carbonModifiers
    }

    init(key: Key, modifiers: NSEvent.ModifierFlags) {
        self.carbonKeyCode = key.carbonKeyCode
        self.carbonModifiers = modifiers.intersection(Self.relevantModifiers).carbonFlags
    }

    var key: Key? { Key(carbonKeyCode: carbonKeyCode) }

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(carbonFlags: carbonModifiers) }

    var keyCombo: KeyCombo { KeyCombo(carbonKeyCode: carbonKeyCode, carbonModifiers: carbonModifiers) }

    /// "⇧⌘V" — standard macOS order ⌃⌥⇧⌘
    var displayString: String {
        Self.modifierSymbols(modifiers) + (key?.description.uppercased() ?? "?")
    }

    static func modifierSymbols(_ modifiers: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols
    }

    /// Shortcut shown next to menu items; nil for keys without a letter or digit equivalent.
    var keyboardShortcut: KeyboardShortcut? {
        guard let description = key?.description, description.count == 1,
              let character = description.lowercased().first,
              character.isLetter || character.isNumber
        else { return nil }

        var eventModifiers: EventModifiers = []
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: eventModifiers)
    }
}
```

- [ ] **Step 5: Реализовать `HotKeyBindingStore`**

Create `Sources/Storage/HotKeyBindingStore.swift`:

```swift
import AppKit
import HotKey

/// Persists hotkey bindings as JSON under a single UserDefaults key.
/// A missing action means "use the default"; an explicit null means "disabled by the user".
struct HotKeyBindingStore {
    static let storageKey = "hotKeys"

    let defaults: UserDefaults

    func binding(for action: HotKeyAction) -> HotKeyBinding? {
        if let stored = load()[action.rawValue] {
            return stored
        }
        return action.defaultBinding
    }

    func save(_ binding: HotKeyBinding?, for action: HotKeyAction) {
        var all = load()
        all[action.rawValue] = .some(binding) // keeps an explicit nil ("disabled")
        write(all)
    }

    func reset(_ action: HotKeyAction) {
        var all = load()
        all.removeValue(forKey: action.rawValue)
        write(all)
    }

    /// Converts the pre-3.0 `hotKeyCode` / `hotKeyModifiers` (raw NSEvent flags) into the
    /// panel binding, then removes the old keys.
    func migrateLegacyIfNeeded() {
        guard let code = defaults.object(forKey: "hotKeyCode") as? Int else { return }

        if load()[HotKeyAction.togglePanel.rawValue] == nil {
            let rawFlags = UInt(defaults.integer(forKey: "hotKeyModifiers"))
            let modifiers = NSEvent.ModifierFlags(rawValue: rawFlags)
                .intersection(HotKeyBinding.relevantModifiers)
            save(
                HotKeyBinding(carbonKeyCode: UInt32(code), carbonModifiers: modifiers.carbonFlags),
                for: .togglePanel
            )
        }
        defaults.removeObject(forKey: "hotKeyCode")
        defaults.removeObject(forKey: "hotKeyModifiers")
    }

    // MARK: - Private

    private func load() -> [String: HotKeyBinding?] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: HotKeyBinding?].self, from: data)
        else { return [:] }
        return decoded
    }

    private func write(_ all: [String: HotKeyBinding?]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
```

- [ ] **Step 6: Запустить тесты**

Run: `swift test --filter HotKeyBindingTests`
Expected: PASS (8 тестов).

- [ ] **Step 7: Commit**

```bash
git add Sources/Models/HotKeyAction.swift Sources/Models/HotKeyBinding.swift Sources/Storage/HotKeyBindingStore.swift \
  Tests/BufrTests/HotKeyBindingTests.swift
git commit -m "$(cat <<'EOF'
feat: модель горячих клавиш с несколькими действиями

HotKeyBinding хранит Carbon-коды, HotKeyBindingStore — JSON в
UserDefaults (null = отключено), старые hotKeyCode/hotKeyModifiers
мигрируются без device-dependent битов.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `HotKeyManager` с несколькими действиями, рекордер и настройки

**Files:**
- Modify: `Sources/Core/HotKeyManager.swift` (переписать целиком)
- Create: `Sources/Views/Common/HotKeyRecorderView.swift`
- Modify: `Sources/Views/Settings/HotKeySettingsView.swift` (переписать целиком)
- Modify: `Sources/App/AppState.swift` (hotkey-раздел и `init`)
- Modify: `Sources/Views/MenuBar/MenuBarView.swift:13-16`
- Modify: `Sources/Resources/{en,ru,uz}.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `HotKeyAction`, `HotKeyBinding`, `HotKeyBindingStore` (Task 6)
- Produces:
  - `@MainActor @Observable final class HotKeyManager`:
    - `init(store: HotKeyBindingStore = HotKeyBindingStore(defaults: .standard))`
    - `private(set) var bindings: [HotKeyAction: HotKeyBinding]`, `var onAction: ((HotKeyAction) -> Void)?`
    - `func registerAll()`, `func setBinding(_: HotKeyBinding?, for: HotKeyAction)`, `func reset(_: HotKeyAction)`, `func suspendAll()`, `func resumeAll()`
  - `struct HotKeyRecorderView: View { let action: HotKeyAction }`
  - `AppState.perform(_ action: HotKeyAction)` (private)

Горячие клавиши регистрируются в Carbon глобально, поэтому эта задача проверяется вручную на собранном приложении, а не юнит-тестами. Логика хранения уже покрыта в Task 6.

- [ ] **Step 1: Переписать `HotKeyManager`**

Заменить содержимое `Sources/Core/HotKeyManager.swift`:

```swift
import AppKit
import HotKey

/// Registers one Carbon hotkey per `HotKeyAction` and reports presses through `onAction`.
@MainActor @Observable
final class HotKeyManager {
    /// Current bindings; an action without an entry is disabled.
    private(set) var bindings: [HotKeyAction: HotKeyBinding] = [:]
    var onAction: ((HotKeyAction) -> Void)?

    @ObservationIgnored private var hotKeys: [HotKeyAction: HotKey] = [:]
    private let store: HotKeyBindingStore

    init(store: HotKeyBindingStore = HotKeyBindingStore(defaults: .standard)) {
        self.store = store
        store.migrateLegacyIfNeeded()
    }

    func registerAll() {
        for action in HotKeyAction.allCases {
            apply(store.binding(for: action), to: action)
        }
    }

    /// `nil` disables the action.
    func setBinding(_ binding: HotKeyBinding?, for action: HotKeyAction) {
        store.save(binding, for: action)
        apply(binding, to: action)
    }

    func reset(_ action: HotKeyAction) {
        store.reset(action)
        apply(store.binding(for: action), to: action)
    }

    /// Unregisters every hotkey (while recording a new one, or during a capture session).
    func suspendAll() {
        hotKeys.values.forEach { $0.isPaused = true }
    }

    func resumeAll() {
        hotKeys.values.forEach { $0.isPaused = false }
    }

    // MARK: - Private

    private func apply(_ binding: HotKeyBinding?, to action: HotKeyAction) {
        hotKeys[action] = nil // deinit unregisters the old Carbon hotkey
        bindings[action] = binding
        guard let binding else { return }

        let hotKey = HotKey(keyCombo: binding.keyCombo)
        hotKey.keyDownHandler = { [weak self] in
            Task { @MainActor in
                self?.onAction?(action)
            }
        }
        hotKeys[action] = hotKey
    }
}
```

- [ ] **Step 2: Создать `HotKeyRecorderView`**

Create `Sources/Views/Common/HotKeyRecorderView.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import HotKey
import SwiftUI

/// Click to record a new shortcut. Esc cancels, ⌫ disables the action.
/// At least one of ⌘ ⌥ ⌃ is required so plain typing is never hijacked.
struct HotKeyRecorderView: View {
    let action: HotKeyAction

    @Environment(AppState.self) private var appState
    @State private var isRecording = false
    @State private var liveModifiers: NSEvent.ModifierFlags = []
    @State private var monitor: Any?

    var body: some View {
        Button {
            if isRecording { stopRecording() } else { startRecording() }
        } label: {
            Text(label)
                .font(.system(.body, design: .monospaced, weight: .medium))
                .foregroundStyle(isRecording ? .secondary : .primary)
                .frame(minWidth: 110)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isRecording ? AnyShapeStyle(Color.accentColor.opacity(0.1)) : AnyShapeStyle(.quinary),
                    in: .rect(cornerRadius: 7)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isRecording ? Color.accentColor : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private var label: String {
        if isRecording {
            return liveModifiers.isEmpty ? L10n("hotkeys.prompt") : HotKeyBinding.modifierSymbols(liveModifiers)
        }
        return appState.hotKeyManager.bindings[action]?.displayString ?? L10n("hotkeys.none")
    }

    private func startRecording() {
        isRecording = true
        // A registered Carbon hotkey would swallow the key press before we see it
        appState.hotKeyManager.suspendAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(HotKeyBinding.relevantModifiers)

        if event.type == .flagsChanged {
            liveModifiers = modifiers
            return event
        }

        let keyCode = Int(event.keyCode)
        if modifiers.isEmpty && keyCode == kVK_Escape {
            stopRecording()
            return nil
        }
        if modifiers.isEmpty && (keyCode == kVK_Delete || keyCode == kVK_ForwardDelete) {
            appState.hotKeyManager.setBinding(nil, for: action)
            stopRecording()
            return nil
        }

        guard !modifiers.intersection([.command, .option, .control]).isEmpty,
              let key = Key(carbonKeyCode: UInt32(event.keyCode))
        else {
            NSSound.beep()
            return nil
        }

        appState.hotKeyManager.setBinding(HotKeyBinding(key: key, modifiers: modifiers), for: action)
        stopRecording()
        return nil
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        liveModifiers = []
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        appState.hotKeyManager.resumeAll()
    }
}
```

- [ ] **Step 3: Переписать `HotKeySettingsView`**

Заменить содержимое `Sources/Views/Settings/HotKeySettingsView.swift`:

```swift
import SwiftUI

struct HotKeySettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section {
                ForEach(HotKeyAction.allCases, id: \.self) { action in
                    HStack {
                        Text(L10n(action.titleKey))

                        Spacer()

                        HotKeyRecorderView(action: action)

                        Button(L10n("hotkeys.reset")) {
                            appState.hotKeyManager.reset(action)
                        }
                        .disabled(appState.hotKeyManager.bindings[action] == action.defaultBinding)
                    }
                }
            } header: {
                Label(L10n("hotkeys.header"), systemImage: "command")
            } footer: {
                Text(L10n("hotkeys.recorder.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(L10n("hotkeys.tip.text"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label(L10n("hotkeys.tip.header"), systemImage: "lightbulb")
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 4: Подключить менеджер в `AppState`**

В `Sources/App/AppState.swift`:

1. Удалить строку `import HotKey`.
2. Удалить раздел `// MARK: - Hotkey Display` вместе со свойством `var hotKeyDisplayString: String = "⌘⇧V"`.
3. В `init` заменить блок

```swift
        // Setup hotkey
        hotKeyManager.onTogglePanel = { [weak self] in
            self?.togglePanel()
        }
        if let code = UserDefaults.standard.object(forKey: "hotKeyCode") as? Int,
           let key = Key(carbonKeyCode: UInt32(code)) {
            let mods = NSEvent.ModifierFlags(rawValue: UInt(UserDefaults.standard.integer(forKey: "hotKeyModifiers")))
            hotKeyManager.register(key: key, modifiers: mods)
        } else {
            hotKeyManager.register()
        }
```

на

```swift
        // Setup hotkeys
        hotKeyManager.onAction = { [weak self] action in
            self?.perform(action)
        }
        hotKeyManager.registerAll()
```

4. Заменить раздел `// MARK: - Hotkey` (методы `resetHotKey()` и `saveHotKey(key:modifiers:)`) на:

```swift
    // MARK: - Hotkey

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .togglePanel:
            togglePanel()
        }
    }
```

- [ ] **Step 5: Показывать в меню текущий хоткей панели**

В `Sources/Views/MenuBar/MenuBarView.swift` заменить

```swift
            Button(L10n("menubar.openPanel")) {
                AppState.shared.togglePanel()
            }
            .keyboardShortcut("V", modifiers: [.command, .shift])
```

на

```swift
            Button(L10n("menubar.openPanel")) {
                AppState.shared.togglePanel()
            }
            .keyboardShortcut(appState.hotKeyManager.bindings[.togglePanel]?.keyboardShortcut)
```

- [ ] **Step 6: Обновить строки во всех трёх языках**

`Sources/Resources/en.lproj/Localizable.strings` — заменить строки:

| Было | Стало |
|---|---|
| `"hotkeys.openPanel" = "Open Panel";` | `"hotkeys.action.togglePanel" = "Open Panel";` |
| `"hotkeys.record" = "Record New Hotkey";` | `"hotkeys.none" = "Not set";` |
| `"menubar.openPanel" = "Open Panel  ⌘⇧V";` | `"menubar.openPanel" = "Open Panel";` |

и после строки `"hotkeys.reset" = "Reset";` добавить:

```
"hotkeys.recorder.hint" = "Click a shortcut to change it. Esc cancels, ⌫ turns it off.";
```

`Sources/Resources/ru.lproj/Localizable.strings`:

| Было | Стало |
|---|---|
| `"hotkeys.openPanel" = "Открыть панель";` | `"hotkeys.action.togglePanel" = "Открыть панель";` |
| `"hotkeys.record" = "Записать новый хоткей";` | `"hotkeys.none" = "Не задано";` |
| `"menubar.openPanel" = "Открыть панель  ⌘⇧V";` | `"menubar.openPanel" = "Открыть панель";` |

после `"hotkeys.reset" = "Сбросить";`:

```
"hotkeys.recorder.hint" = "Нажмите на сочетание, чтобы изменить его. Esc — отмена, ⌫ — отключить.";
```

`Sources/Resources/uz.lproj/Localizable.strings`:

| Было | Стало |
|---|---|
| `"hotkeys.openPanel" = "Panelni ochish";` | `"hotkeys.action.togglePanel" = "Panelni ochish";` |
| `"hotkeys.record" = "Yangi tezkor tugma yozish";` | `"hotkeys.none" = "Belgilanmagan";` |
| `"menubar.openPanel" = "Panelni ochish  ⌘⇧V";` | `"menubar.openPanel" = "Panelni ochish";` |

после `"hotkeys.reset" = "Tiklash";`:

```
"hotkeys.recorder.hint" = "O‘zgartirish uchun birikmani bosing. Esc — bekor qilish, ⌫ — o‘chirish.";
```

Проверить, что старые ключи нигде не используются:

Run: `grep -rn '"hotkeys.openPanel"\|"hotkeys.record"' Sources`
Expected: пустой вывод.

- [ ] **Step 7: Сборка и тесты**

Run: `swift build && swift test`
Expected: `Build complete!`, все тесты PASS.

- [ ] **Step 8: Ручная проверка на собранном приложении**

Run: `./scripts/build-app.sh debug && open Bufr.app`

Проверить:
1. ⌘⇧V открывает и закрывает панель.
2. Настройки → «Горячие клавиши»: строка «Открыть панель» показывает `⇧⌘V`, кнопка «Сбросить» неактивна.
3. Нажать на сочетание: появляется «Нажмите комбинацию клавиш…». Зажать ⌥⌘ — видно `⌥⌘`. Нажать B — сохранилось `⌥⌘B`, ⌥⌘B открывает панель, ⌘⇧V больше не открывает.
4. Во время записи нажать букву без модификаторов — звук ошибки, запись продолжается. Esc — запись отменена, сочетание прежнее.
5. Нажать на сочетание и ⌫ — «Не задано», панель по хоткею не открывается, в меню строки меню у «Открыть панель» нет сочетания.
6. «Сбросить» — снова `⇧⌘V`.
7. Задать ⌥⌘B, выйти из Bufr (⌘Q в меню) и запустить снова: в настройках `⌥⌘B`, и хоткей работает. Раньше после перезапуска показывался «⌘⇧V».
8. Миграция со старой версии: выйти из Bufr, выполнить
   `defaults delete com.bufr.app hotKeys; defaults write com.bufr.app hotKeyCode -int 11; defaults write com.bufr.app hotKeyModifiers -int 1572864`,
   запустить Bufr. Ожидается ⌥⌘B в настройках, хоткей работает, `defaults read com.bufr.app hotKeyCode` сообщает, что ключа нет. (1572864 = ⌘ | ⌥ в NSEvent.)

- [ ] **Step 9: Commit**

```bash
git add Sources/Core/HotKeyManager.swift Sources/Views/Common/HotKeyRecorderView.swift \
  Sources/Views/Settings/HotKeySettingsView.swift Sources/App/AppState.swift Sources/Views/MenuBar/MenuBarView.swift \
  Sources/Resources/en.lproj/Localizable.strings Sources/Resources/ru.lproj/Localizable.strings \
  Sources/Resources/uz.lproj/Localizable.strings
git commit -m "$(cat <<'EOF'
feat: HotKeyManager с несколькими действиями и новый рекордер

Сочетание сохраняется и отображается после перезапуска, модификаторы
показываются при записи, ⌫ отключает хоткей, в меню строки меню
отображается текущее сочетание вместо жёстко прописанного ⌘⇧V.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: `AppActivation` и `SettingsWindowController` вместо сцены `Settings`

**Files:**
- Create: `Sources/App/AppActivation.swift`
- Create: `Sources/Views/Settings/SettingsWindowController.swift`
- Modify: `Sources/Views/Settings/SettingsView.swift`
- Modify: `Sources/App/BufrApp.swift`
- Modify: `Sources/App/AppState.swift` (удалить `openSettingsWindow()`)
- Modify: `Sources/Views/PanelWindow/ClipPanelView.swift:5`, `:352-378`
- Modify: `Sources/Views/MenuBar/MenuBarView.swift` (`openSettings`)
- Modify: `Sources/Resources/{en,ru,uz}.lproj/Localizable.strings`

**Interfaces:**
- Consumes: —
- Produces:
  - `@MainActor enum AppActivation { static func present(_ window: NSWindow) }` — редактор (M4) и гайды разрешений (M1) показываются через него же
  - `enum SettingsTab: String, CaseIterable, Identifiable` (internal)
  - `@MainActor @Observable final class SettingsSelection { var tab: SettingsTab }`
  - `@MainActor final class SettingsWindowController { static let shared; func show(tab: SettingsTab? = nil) }`
  - `SettingsView(selection: SettingsSelection)`

Это поведение окон AppKit, поэтому проверка ручная.

- [ ] **Step 1: Создать `AppActivation`**

Create `Sources/App/AppActivation.swift`:

```swift
import AppKit

/// Bufr runs as an accessory (menu bar) app. While a regular window such as Settings is open,
/// the app switches to `.regular` so the window gets focus, a Dock icon and the standard menus,
/// then switches back when the last such window closes.
@MainActor
enum AppActivation {
    private static var openWindows: Set<ObjectIdentifier> = []
    private static var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    static func present(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        if openWindows.insert(id).inserted {
            closeObservers[id] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    windowWillClose(id)
                }
            }
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
    }

    private static func windowWillClose(_ id: ObjectIdentifier) {
        openWindows.remove(id)
        if let observer = closeObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
        if openWindows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
```

- [ ] **Step 2: Сделать вкладку настроек управляемой извне**

В `Sources/Views/Settings/SettingsView.swift`:

1. Заменить `private enum SettingsTab: String, CaseIterable, Identifiable {` на `enum SettingsTab: String, CaseIterable, Identifiable {`.
2. После enum добавить:

```swift
/// Selected Settings tab, shared with SettingsWindowController so code can open a specific tab.
@MainActor @Observable
final class SettingsSelection {
    var tab: SettingsTab = .general
}
```

3. В `struct SettingsView` заменить `@State private var selectedTab: SettingsTab = .general` на `@Bindable var selection: SettingsSelection`.
4. Заменить `List(SettingsTab.allCases, selection: $selectedTab) { tab in` на `List(SettingsTab.allCases, selection: $selection.tab) { tab in`, а `switch selectedTab {` — на `switch selection.tab {`.

- [ ] **Step 3: Создать `SettingsWindowController`**

Create `Sources/Views/Settings/SettingsWindowController.swift`:

```swift
import AppKit
import SwiftUI

/// Owns the Settings window. Replaces the SwiftUI `Settings` scene so any code
/// (panel, menu bar, permission guides) can open Settings on a specific tab.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private let selection = SettingsSelection()
    private var window: NSWindow?

    private init() {}

    func show(tab: SettingsTab? = nil) {
        if let tab {
            selection.tab = tab
        }
        let window = self.window ?? makeWindow()
        self.window = window
        window.title = L10n("settings.window.title") // language may have changed since creation
        AppActivation.present(window)
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsView(selection: selection)
            .environment(AppState.shared)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 680, height: 600)) // SettingsView's fixed frame
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
```

- [ ] **Step 4: Убрать сцену `Settings` и обходные пути с фокусом**

Заменить содержимое `Sources/App/BufrApp.swift`:

```swift
import SwiftUI

@main
struct BufrApp: App {
    var body: some Scene {
        MenuBarExtra("Bufr", systemImage: "clipboard") {
            MenuBarView()
                .environment(AppState.shared)
        }
    }
}
```

В `Sources/App/AppState.swift` удалить метод `openSettingsWindow()` целиком (он не используется, а селектор `showSettingsWindow:` для SwiftUI-сцены на macOS 14+ не работает).

В `Sources/Views/PanelWindow/ClipPanelView.swift`:
1. Удалить строку `@Environment(\.openSettings) private var openSettings`.
2. В `actionButtons` заменить действие кнопки с шестерёнкой (от `appState.hidePanel()` до закрывающей `}` блока `Task { @MainActor in … }`) на:

```swift
            Button {
                appState.hidePanel()
                SettingsWindowController.shared.show()
            } label: {
```

Label кнопки (`Image(systemName: "gearshape")…`) не меняется.

В `Sources/Views/MenuBar/MenuBarView.swift`:
1. Удалить строку `@Environment(\.openSettings) private var openSettings`.
2. Заменить кнопку проверки обновлений на:

```swift
            Button(L10n("menubar.checkUpdates")) {
                Task {
                    await AppState.shared.updater.checkForUpdates()
                }
                SettingsWindowController.shared.show(tab: .updates)
            }
```

3. Заменить кнопку настроек на:

```swift
            Button(L10n("menubar.settings")) {
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",", modifiers: .command)
```

- [ ] **Step 5: Строка заголовка окна**

После строки `"settings.tab.about" = …;` в каждом файле добавить:

- en: `"settings.window.title" = "Bufr Settings";`
- ru: `"settings.window.title" = "Настройки Bufr";`
- uz: `"settings.window.title" = "Bufr sozlamalari";`

- [ ] **Step 6: Сборка и тесты**

Run: `swift build && swift test`
Expected: `Build complete!`, все тесты PASS.

Run: `grep -rn "openSettings\|showSettingsWindow" Sources`
Expected: пустой вывод.

- [ ] **Step 7: Ручная проверка**

Run: `./scripts/build-app.sh debug && open Bufr.app`

Проверить:
1. Шестерёнка в панели: панель закрывается, окно «Настройки Bufr» открывается поверх остальных окон и в фокусе, в Dock появляется иконка.
2. Закрыть окно: иконка из Dock исчезает, фокус возвращается предыдущему приложению.
3. Меню строки меню → «Настройки…»: то же поведение. Повторный вызов при открытом окне не создаёт второе окно, а выводит существующее вперёд.
4. «Проверить обновления»: открывается вкладка «Обновления».
5. Переключить язык в «Основных»: интерфейс окна перерисовывается (как раньше).
6. Открыть настройки, находясь на другом рабочем столе (Space): окно появляется на текущем.

- [ ] **Step 8: Commit**

```bash
git add Sources/App/AppActivation.swift Sources/Views/Settings/SettingsWindowController.swift \
  Sources/Views/Settings/SettingsView.swift Sources/App/BufrApp.swift Sources/App/AppState.swift \
  Sources/Views/PanelWindow/ClipPanelView.swift Sources/Views/MenuBar/MenuBarView.swift \
  Sources/Resources/en.lproj/Localizable.strings Sources/Resources/ru.lproj/Localizable.strings \
  Sources/Resources/uz.lproj/Localizable.strings
git commit -m "$(cat <<'EOF'
refactor: окно настроек через SettingsWindowController

Одна точка открытия настроек с выбором вкладки вместо трёх обходных
путей с фокусом. AppActivation переключает .regular/.accessory, пока
открыты обычные окна.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Приёмка этапа M0

**Files:**
- Modify: `docs/superpowers/specs/2026-09-23-screenshots-design.md` (раздел «Этапы», строка M0: отметить перенос `SystemShortcutInspector`/`PermissionsManager`/`AppRelauncher` в M1)

**Interfaces:**
- Consumes: всё из Tasks 1–8
- Produces: ветку `feature/screenshots`, готовую к плану M1

- [ ] **Step 1: Полный прогон**

Run: `swift build -c release && swift test`
Expected: `Build complete!`; все тесты PASS (41 тест в 9 наборах).

- [ ] **Step 2: Регрессия на собранном приложении**

Run: `./scripts/build-app.sh debug && open Bufr.app`

Проверить (приложение должно вести себя как 2.x, кроме исправленных багов):
1. Скопировать текст в TextEdit — карточка появляется в течение секунды, звук (если включён) играет.
2. Скопировать картинку (⌘C в Preview) — карточка с миниатюрой. В `~/Library/Application Support/Bufr/images` появился файл `<id>.png`, который открывается в Preview как PNG.
3. Скопировать ту же картинку ещё раз — карточка поднялась наверх, второго файла нет.
4. Вставить старый элемент из середины истории (Enter в панели) — он вставился в активное приложение, поднялся наверх, **новой карточки-дубля нет** (подождать 2 секунды). То же для картинки.
5. Контекстное меню карточки → «Копировать» — ⌘V в TextEdit вставляет содержимое, карточка наверху, дубля нет.
6. Меню строки меню → элемент-картинка из списка — ⌘V в Pages/TextEdit вставляет картинку.
7. Скопировать пароль из «Связки ключей»/1Password — в историю не попадает.
8. Удалить картинку из истории — её файл и миниатюра исчезли из `images/` и `thumbnails/`.
9. Экспорт доски в `.bufr` и импорт обратно работают; импорт `.bufr`, созданного в 2.x (если есть под рукой), тоже.
10. Поиск в панели находит старые текстовые записи (история после обновления со схемы v3).

- [ ] **Step 3: Отметить отклонение в спецификации**

В `docs/superpowers/specs/2026-09-23-screenshots-design.md`, в таблице раздела «Этапы», ячейку «Содержимое» строки **M0** дополнить в конце фразой:

```
(SystemShortcutInspector, PermissionsManager и AppRelauncher перенесены в M1 — к первому потребителю)
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-09-23-screenshots-design.md docs/superpowers/plans/2026-09-23-screenshots-m0-foundations.md
git commit -m "$(cat <<'EOF'
docs: спецификация скриншотов и план этапа M0

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```
