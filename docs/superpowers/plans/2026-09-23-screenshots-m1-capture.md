# Bufr 3.0 — M1 «Захват»: план реализации

> Выполняется инлайн (superpowers:executing-plans) прямо в `main` — так решил пользователь.
> Шаги по TDD: для чистой логики тест пишется первым и должен упасть. AppKit/ScreenCaptureKit-части
> (оверлей, окна, захват) проверяются сборкой и ручным чек-листом пользователя: в сессии нет GUI.

**Goal:** Сделать первые видимые скриншоты:
- ⌘⇧3 снимает экран, ⌘⇧4 — область; Space переключает режим окна; Return снимает прошлую область;
- у выделения есть лупа и размер в пикселях;
- PNG сохраняется в `~/Pictures/Bufr` и копируется в буфер, снимок сразу становится карточкой истории;
- в панели есть вкладка «Скриншоты»; в меню строки меню — пункты захвата;
- хоткей, занятый включённым системным сочетанием macOS, не регистрируется и показывается как «занято macOS»;
- без разрешения «Запись экрана» открывается гид.

**Spec:** [2026-09-23-screenshots-design.md](../specs/2026-09-23-screenshots-design.md): разделы M1, D1–D7, D12, D16.

**Architecture:**
- `CaptureSessionController` управляет одной сессией: разрешение → freeze-кадры → оверлеи → выбор → результат `CaptureOutcome`.
- `ScreenshotCoordinator` — вход из хоткеев и меню и постобработка: PNG, `ClipIngestor`, файл, буфер, звук, прошлая область.
- Вся математика вынесена в чистые типы и покрыта тестами: `ScreenGeometry`, `SelectionGeometry`, `WindowPicker`, `WindowListProvider.parse`, `ScreenshotFilenameFormatter`, `SystemShortcutInspector.parse`, `PermissionsManager.status`.

## Global Constraints
- Всё из M0 (Swift 6 strict, стиль, L10n в ru/en/uz, коммиты на русском с Co-Authored-By, конкретные файлы в `git add`).
- ScreenCaptureKit — только через `@preconcurrency import ScreenCaptureKit` на `@MainActor`. Между акторами передаются только `CGImage`, `Data` и value-типы.
- Координаты:
  - CG-глобальные — начало в левом верхнем углу основного дисплея, y вниз;
  - Cocoa-глобальные — начало в левом нижнем, y вверх;
  - `H = NSScreen.screens[0].frame.height`, **не** `NSScreen.main`;
  - локальные координаты выделения хранятся в точках дисплея с началом **сверху слева**.
- Оверлей — layer-hosting `NSView`, не flipped. Все слои в координатах Core Animation (снизу слева), перевод в «сверху слева» делается только на границе с `ScreenGeometry`.
- Своё приложение исключается из кадра через `SCContentFilter(display:excludingApplications:exceptingWindows:)`. В M2 в `exceptingWindows` попадут закреплённые снимки.
- Снимок вставляется без дедупликации (`deduplicate: false`, D16) с `origin = .screenshot`.
- По умолчанию: папка `~/Pictures/Bufr`, копирование в буфер включено, звук включён, тень окна включена, курсор выключен, Retina → 1x выключено.
- Отладочные сборки не трогают данные установленного приложения (M0: `AppPaths`, `com.bufr.app.debug`).

## Review Focus
1. **Второй дисплей слева или сверху** (отрицательные CG-координаты): выделение, подсветка окна и кроп должны попадать в нужные пиксели. Тесты `ScreenGeometryTests.secondaryDisplayLeftAndAbove`, `pixelRectOnFractionalScale`.
2. **Системные ⌘⇧3/⌘⇧4 включены:** хоткей Bufr не регистрируется, двойного снимка нет, после отключения системных хоткей регистрируется. Тесты `HotKeyManagerConflictTests`.
3. **Отсутствующий ID в `com.apple.symbolichotkeys` означает «включён по умолчанию».** Тест `SystemShortcutInspectorTests.missingIdMeansEnabledDefault`.
4. **Одинаковые имена файлов в одну секунду:** второй файл получает « (2)», ничего не перезаписывается. Тест `ScreenshotFileWriterTests.neverOverwrites`.
5. **Повторный хоткей или Esc во время сессии:** сессия отменяется, хоткеи и фокус возвращаются. Проверяется в ручном чек-листе; guard-логика — в тесте `CaptureSessionStateTests`.

---

## Задачи

### Task 1: Хранилище — скриншоты в истории
- Modify `Sources/Storage/ClipItemStore.swift`: добавить
  - `fetchItems(origin: ClipOrigin, limit: Int = 200) throws -> [ClipItem]`;
  - `search(query: String, origin: ClipOrigin?) throws -> [ClipItem]` — старый `search(query:)` вызывает его с `nil`;
  - `setSavedFilePath(_ path: String?, for id: UUID) throws` — узкий UPDATE одной колонки плюс обновление строки в `items`.
- Modify `Sources/Models/ClipItem.swift`: добавить `isScreenshot`, `pixelSizeText` («2880 × 1800»); `displayTitle` для скриншота без `customTitle` возвращает `L10n("contentType.screenshot")`.
- Tests в `ClipItemStoreTests`: `fetchItemsFiltersByOrigin`, `searchWithinOrigin`, `setSavedFilePathKeepsOtherFields`, `pixelSizeText`.

### Task 2: `ScreenGeometry` и `SelectionGeometry`
- Create `Sources/Capture/ScreenGeometry.swift`: `cgRect(fromCocoa:primaryHeight:)`, `cocoaRect(fromCG:primaryHeight:)`, `cgPoint(fromCocoa:primaryHeight:)`, `topLeftRect(fromBottomLeft:in height:)`, `pixelRect(forLocal:displayPointSize:imagePixelSize:)` (floor/ceil, clamp, результат `.null`, если пусто).
- Create `Sources/Capture/SelectionGeometry.swift`: `rect(from:to:square:fromCenter:bounds:)` и `moved(_:by:within:)`.
- Tests: `ScreenGeometryTests`, `SelectionGeometryTests`.

### Task 3: Окна под курсором
- Create `Sources/Capture/CapturableWindow.swift` (struct), `Sources/Capture/WindowListProvider.swift` (`parse(_ info: [[String: Any]], excludingPID:) -> [CapturableWindow]` + `snapshot()`), `Sources/Capture/WindowPicker.swift` (`window(at:in:)`).
- Tests: `WindowPickerTests` (front-to-back, промах), `WindowListProviderTests` (слой ≠ 0, alpha 0, меньше 40pt, свой PID).

### Task 4: Имена файлов, запись, PNG c DPI, настройки
- Create `Sources/Screenshots/ScreenshotFilenameFormatter.swift`, `Sources/Screenshots/ScreenshotFileWriter.swift`, `Sources/Screenshots/ScreenshotSettings.swift`.
- Modify `Sources/Utilities/ImageEncoder.swift`: `pngData(from: CGImage, pointScale: CGFloat, downscaleToOneX: Bool) -> Data?`.
- Tests: `ScreenshotFilenameFormatterTests`, `ScreenshotFileWriterTests`, `ImageEncoderTests.pngCarriesRetinaDPI` / `downscaleHalvesPixels`, `ScreenshotSettingsTests`.

### Task 5: Системные сочетания и хоткеи захвата с учётом конфликтов
- Create `Sources/Core/SystemShortcutInspector.swift` (`parse`, `enabledScreenshotShortcuts()`).
- Modify `HotKeyAction`: добавить `captureFullscreen` (⌘⇧3), `captureArea` (⌘⇧4), `captureWindow` (без сочетания), `capturePreviousArea` (без сочетания); добавить `group` (панель / скриншоты).
- Modify `HotKeyManager`:
  - в `init` внедряется `systemShortcuts: () -> Set<HotKeyBinding>`;
  - `blockedBySystem`, `isRegistered(_:)`, `recheckSystemConflicts()`, `action(using:excluding:)` для поиска дублей;
  - таймер перепроверки раз в 10 с, пока есть заблокированные.
- Modify `HotKeyRecording`: дубль сочетания отклоняется звуком и не записывается.
- Tests: `SystemShortcutInspectorTests`, `HotKeyManagerConflictTests`.

### Task 6: Разрешения
- Create `Sources/Core/PermissionsManager.swift`: `status(granted:requestedBefore:grantedBuild:currentBuild:)` (чистая), `refresh()`, `requestScreenCapture()`, `recordGrantIfNeeded()`, deep links, `resetScreenCapture()` (tccutil).
- Create `Sources/App/AppRelauncher.swift`.
- Tests: `PermissionsStatusTests`.

### Task 7: ScreenCaptureKit и сессия захвата
- Create:
  - `Sources/Capture/CaptureMode.swift` (`CaptureMode`, `CaptureOutcome`, `CaptureSelection`);
  - `Sources/Capture/DisplayInfo.swift` (`NSScreen.displayID`, `displayUUID(for:)`, `displayID(forUUID:)`);
  - `Sources/Capture/ScreenCaptureService.swift`;
  - `Sources/Capture/PreviousAreaStore.swift`;
  - `Sources/Capture/CaptureSessionController.swift`.
- Кроп — чистая функция `ScreenCaptureService.crop(_:localRect:displayPointSize:)`, покрыта тестом.
- Tests: `PreviousAreaStoreTests`, `CropTests`, `CaptureSessionStateTests` (повторный запуск отменяет текущую сессию; без разрешения оверлей не показывается).

### Task 8: Оверлей выделения
- Create `Sources/Capture/Overlay/CaptureOverlayWindow.swift` и `Sources/Capture/Overlay/CaptureOverlayView.swift`: layer-hosting; слои кадра, затемнения, рамки, подсветки, лупы, размера; мышь, Space, Esc, Return.
- Проверка: сборка и ручной чек-лист.

### Task 9: Координатор и постобработка
- Create `Sources/Screenshots/ScreenshotCoordinator.swift`: `capture(_ mode: CaptureMode)`, `openScreenshotsFolder()`, `revealInFinder(_ item: ClipItem)`.
- Create `Sources/Screenshots/ShutterSound.swift`.
- Modify `AppState`: создать `screenshotSettings`, `permissions`, `screenshots`; `perform(_:)` обрабатывает действия захвата.
- Tests: `ScreenshotPipelineTests` — выполняет `process(outcome:)` без SCK: карточка в истории, файл в папке, в буфере PNG с маркером.

### Task 10: UI
- Create:
  - `Sources/Views/Settings/ScreenshotSettingsView.swift`;
  - `Sources/Views/Common/SystemShortcutsBanner.swift`;
  - `Sources/Views/Onboarding/PermissionGuideView.swift` + `PermissionGuideWindowController`.
- Modify:
  - `SettingsView`: вкладка `.screenshots`;
  - `HotKeySettingsView`: группы и баннер;
  - `ClipPanelView`: вкладка «Скриншоты», пустое состояние;
  - `ClipCardView`: бейдж, размер, «Показать в Finder»;
  - `MenuBarView`: пункты захвата, «Открыть папку», предупреждение о разрешении;
  - `Localizable.strings` ×3.
- Проверка: сборка, `plutil -lint`, совпадение ключей ru/en/uz (тест `LocalizationParityTests`).

### Task 11: Приёмка M1
- `swift build -c release`, `swift test`, `./scripts/build-app.sh debug`, пробный запуск `Bufr-Debug.app` и ручной чек-лист для пользователя.
