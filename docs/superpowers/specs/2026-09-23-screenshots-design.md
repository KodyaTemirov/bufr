# Bufr 3.0 — скриншоты в стиле CleanShot X

## Контекст

Bufr сейчас — менеджер буфера обмена. Цель: добавить работу со скриншотами по образцу CleanShot X (захват, оверлей после снимка, редактор аннотаций, OCR, закрепление на экране) и встроить их в историю буфера. Главное отличие от CleanShot: каждый снимок сразу становится карточкой в истории, а текст на всех картинках ищется через FTS. Выпуск одним релизом **v3.0.0**. Внутри работа идёт этапами M0–M5, и после каждого этапа приложение собирается и запускается.

### Решения пользователя
| Вопрос | Решение |
|---|---|
| Объём v1 | Захват (область / окно / экран / прошлая область / меню режимов ⌘⇧5) + оверлей после снимка + редактор + OCR + закрепление на экране |
| Не входит в v1 | Запись экрана/GIF, скроллинг-захват, облако, Background tool, таймер |
| История | Каждый скриншот **всегда** попадает в историю, в панели есть вкладка «Скриншоты» |
| Файлы | Автосохранение PNG в папку и одновременно в историю |
| Хоткеи | Заменяем системные: ⌘⇧3 экран, ⌘⇧4 область (Space переключает на окно), ⌘⇧5 меню режимов, ⌘⇧2 OCR. Все переназначаемые |
| OCR-поиск | Фоновое распознавание **всех** картинок в истории (включая уже существующие), текст идёт в FTS5 |
| Правки | Слои можно переделать: оригинал и аннотации хранятся отдельно |
| Выделение | Свой оверлей (заморозка кадра, лупа, подсветка окон), не `screencapture` |
| Подпись | Остаётся ad-hoc, поэтому после каждого обновления нужен UX повторной выдачи разрешения |

---

## Ключевые технические решения

| # | Решение | Почему |
|---|---|---|
| D1 | Скриншот = `ContentType.image` + новая nullable колонка `origin` (`clipboard`/`screenshot`/`textCapture`) | Новый case задел бы 8+ `switch` (ContentType, HashGenerator, ClipboardPaster, ClipCardView, QuickPreviewView, MenuBarView). Вставка, превью и миниатюры работают без изменений |
| D2 | Папка по умолчанию `~/Pictures/Bufr` (Desktop можно выбрать) | Desktop защищён TCC. С ad-hoc подписью это разрешение сбрасывалось бы при каждом обновлении |
| D3 | Одна миграция `v4_screenshotsAndOCR` добавляется сразу в M0 | В DEBUG `eraseDatabaseOnSchemaChange` стирает БД при правке миграции |
| D4 | Freeze-frame через `SCScreenshotManager.captureScreenshot(contentFilter:configuration:)` (macOS 26), по кадру на дисплей, **до** показа оверлея | `CGWindowListCreateImage` устарел в macOS 15. Системный запрос согласия не окажется под нашим оверлеем |
| D5 | Область = кроп freeze-кадра. Окно = `SCContentFilter(desktopIndependentWindow:)` с прозрачной тенью | Область совпадает с тем, что видел пользователь. Окно выходит чистым, как в macOS/CleanShot |
| D6 | Выделение ограничено одним дисплеем | Не нужно склеивать дисплеи с разным масштабом. Так же ведёт себя нативный ⌘⇧4 |
| D7 | На время захвата Bufr активируется, потом возвращает фокус предыдущему приложению | Надёжные клавиши, курсор и first responder |
| D8 | Холст редактора — AppKit `NSView` в `NSScrollView`, тулбар и инспектор на SwiftUI | Точная мышь и модификаторы, inline `NSTextView`, зум, базовый слой без перерисовки. SwiftUI Canvas перерисовывает всё |
| D9 | Один `AnnotationRenderer` (CoreGraphics) и для экрана, и для экспорта | WYSIWYG и тесты на пиксели |
| D10 | SwiftUI-сцену `Settings` заменяем на `SettingsWindowController.shared.show(tab:)` | Потоки разрешений должны открывать конкретную вкладку из AppKit-кода. Заодно уходят 3 существующих обходных пути с фокусом |
| D11 | Маркер собственных записей `com.bufr.app.self-write` в pasteboard; `ClipboardMonitor` такие изменения пропускает | Иначе монитор повторно ловит наши копирования (сейчас это баг и для картинок) |
| D12 | Хоткей захвата, совпадающий с **включённым** системным (symbolichotkeys 28–31, 184), не регистрируется. Показываем «занято macOS». После отключения системного он регистрируется автоматически | Если зарегистрированы оба, поведение не определено (двойной снимок) |
| D13 | Добавляем `.testTarget BufrTests` → `@testable import Bufr` поверх executableTarget | Разделение на library переименовало бы `Bufr_Bufr.bundle`, от которого зависят `L10n.swift` и `build-app.sh` |
| D14 | Фоновый OCR пишет только в БД, в `items` в памяти не трогает | Любое изменение `items` сбрасывает выделение в панели (`ClipPanelView.swift:114-118`) |
| D15 | Аннотации: `<uuid>_orig.png` + `<uuid>.annotations.json`; плоский рендер **заменяет** `<uuid>.png` и миниатюру | Существующий код карточек, вставки, экспорта и миниатюр работает без изменений |
| D16 | Скриншоты вставляются без дедупликации | Два одинаковых снимка — два разных события |
| D17 | Логика скриншотов — в `ScreenshotCoordinator`, настройки — в `ScreenshotSettings` (не в AppState) | AppState уже 273 строки |

### Баги, которые чиним попутно (мешают новой функциональности)
1. UUID файла картинки ≠ `ClipItem.id` (`ClipboardMonitor.swift:92` и `:114`), поэтому при удалении миниатюры остаются сиротами.
2. При дедупликации остаётся файл-сирота: `saveImage` вызывается до проверки хеша.
3. В файлах `.png` может лежать TIFF (`ContentTypeDetector.swift:60-68`). При загрузке конвертируем в настоящий PNG.
4. Вставка картинки из истории создаёт дубль (TIFF с другими байтами). Лечится маркером D11 и явным `touch(item)`.
5. Рекордер хоткея сохраняет сырые `modifierFlags`. Маскируем до `[.command,.option,.control,.shift]`.
6. Строка хоткея не восстанавливается после перезапуска, в меню жёстко прописано «⌘⇧V».
7. Перетаскивание карточки-картинки тащит строку с именем файла, а «Копировать» в меню строки меню для картинок ничего не копирует.

---

## Структура модулей (N — новый, M — изменённый)

```
Sources/
  App/        AppState M (owns screenshots, permissions, ocrIndexer; dispatch HotKeyAction)
              BufrApp M (только MenuBarExtra), AppActivation N (.regular/.accessory с подсчётом ссылок), AppRelauncher N
  Core/       ClipIngestor N (единый путь загрузки картинок и текста), PasteboardWriter N (маркер D11, ленивый TIFF)
              ClipboardMonitor M, ClipboardPaster M, HotKeyManager M (переписан: несколько действий)
              PermissionsManager N, SystemShortcutInspector N, ToastPresenter N
  Models/     ClipItem M (+origin, ocrText, annotationPath, savedFilePath, pixelWidth, pixelHeight — все Optional)
              ClipOrigin N, HotKeyAction N, HotKeyBinding N
  Storage/    AppDatabase M (v4), ClipItemStore M, ImageStorage M (injectable baseDirectory, replaceImage, deleteAssets), AppPaths N
  Capture/    CaptureMode, ScreenGeometry, DisplayInfo, ScreenCaptureService, WindowListProvider, WindowPicker,
              CaptureExclusionRegistry, CaptureSessionController, PreviousAreaStore
              Overlay/ CaptureOverlayWindow, CaptureOverlayView, LoupeLayer, SelectionGeometry, AllInOneToolbarView
  Screenshots/ ScreenshotCoordinator, ScreenshotService, ScreenshotSettings, ScreenshotFilenameFormatter,
              ScreenshotFileWriter, ImageEncoder, ShutterSound
  QuickAccess/ QuickAccessController, QuickAccessPanel, QuickAccessStackView, QuickAccessCardView
  ScreenPin/  ScreenPinManager, ScreenPinPanel, ScreenPinView   (название «ScreenPin», чтобы не путать с isPinned и Pinboards)
  OCR/        OCRService, OCRTextAssembler, OCRIndexer (actor), OCRSettings
  Editor/     Model/ (AnnotationDocument, Annotation, AnnotationStyle, AnnotationTool)
              Geometry/ (AnnotationGeometry, ArrowGeometry, PathSmoothing)
              Rendering/ (AnnotationRenderer, EffectRenderer, CGContext+TopLeft)
              Canvas/ (AnnotationCanvasView, CanvasInteraction, TextAnnotationEditor, CanvasContainer)
              Window/ (EditorWindowManager, EditorWindowController, EditorViewModel, EditorRootView, EditorToolbarView, EditorStyleBar)
              Persistence/ AnnotationStore
  Views/      Common/ HotKeyRecorderView, PermissionStatusRow, SystemShortcutsBanner
              Settings/ SettingsWindowController N, SettingsView M, HotKeySettingsView M (переписан),
                        ScreenshotSettingsView N, PermissionsSettingsView N
              Onboarding/ ScreenshotSetupView N, PermissionGuideView N
              PanelWindow/ PanelTabsView N (вынесен из ClipPanelView :235-349, :592-687), ClipPanelView M, ClipCardView M,
                        ClipCardContextMenu N, ClipImageTransferable N, ImageCardContent M, QuickPreviewView M
              MenuBar/ MenuBarView M
Tests/BufrTests/   (Swift Testing) + Fixtures/
```

---

## Данные

**Миграция `v4_screenshotsAndOCR`** в [AppDatabase.swift](Sources/Storage/AppDatabase.swift) повторяет шаблон `v2_addCustomTitle`:
- `ALTER clip_items ADD origin TEXT, ocr_text TEXT, annotation_path TEXT, saved_file_path TEXT, pixel_width INTEGER, pixel_height INTEGER`. У `ocr_text`: NULL = ещё не обработано, `""` = обработано, текста нет.
- Индексы: `(origin, created_at)` и частичный `ON clip_items(created_at) WHERE content_type='image' AND ocr_text IS NULL`.
- Удаляем триггеры `__clip_items_fts_{ai,ad,au}` и FTS-таблицу, пересоздаём FTS5 с `text_content, source_app_name, custom_title, ocr_text`.

**ClipItem**: новые поля добавляем в `Columns` и в `CodingKeys`. Все Optional, потому что Codable — это ещё и формат экспорта `.bufr`. `PinboardExportService.swift:260,474` переносят `origin`/`ocrText`, а локальные пути обнуляют.

**ClipItemStore**: `existingItem(hash:)`, `insert(_:deduplicate:)`, `touch(_:)`, `update(_:)`, `item(id:)`, `fetchItems(origin:)`, `search(query:origin:)`, `ocrText(for:)`. Очистка по сроку хранения удаляет все ассеты через `ImageStorage.deleteAssets`. Файл в пользовательской папке не трогаем.

---

## Подсистемы

### M0 — Фундамент
- **ClipIngestor** (`@MainActor`, зависимости внедряются): `ingestImage(ImageInput) async throws -> ClipItem` работает так: хеш по исходным байтам → если дубль, `touch` без записи файла → нормализация в PNG и размер в пикселях → `saveImage(png, id: input.id)` (тот же UUID) → insert → `prependItem` → `ocrIndexer.enqueue`. Ещё `ingestText(...)`. Логику `saveClipItem` переносим сюда из [ClipboardMonitor.swift:109-134](Sources/Core/ClipboardMonitor.swift#L109-L134).
- **PasteboardWriter**: всегда добавляет маркер; PNG кладёт сразу, TIFF — лениво через `NSPasteboardItemDataProvider`. `ClipboardMonitor.checkForChanges` выходит рано, если видит маркер.
- **HotKeyManager** (переписан): `enum HotKeyAction { togglePanel, captureArea, captureWindow, captureFullscreen, capturePreviousArea, captureAllInOne, captureText }`, `[HotKeyAction: HotKey]`, `onAction`, `setBinding/reset/resetAll/suspendAll/resumeAll` (через `HotKey.isPaused`), `recheckSystemConflicts()`. Хранение: один ключ UserDefaults `"hotKeys"` с JSON `[String: HotKeyBinding?]`, где `null` = отключён. Старые `hotKeyCode`/`hotKeyModifiers` мигрируем.
- **SystemShortcutInspector**: чистая функция `parse(_:)` над `CFPreferencesCopyAppValue("AppleSymbolicHotKeys", "com.apple.symbolichotkeys")`. ID 28/29/30/31/184; **отсутствующий ID значит «включён по умолчанию»** (на этой машине 184 отсутствует). Для общих конфликтов — `KeyCombo.systemKeyCombos()` из HotKey (проверено: API есть).
- **PermissionsManager** (`@MainActor @Observable`): `CGPreflightScreenCaptureAccess`/`CGRequestScreenCaptureAccess`, `AXIsProcessTrusted[WithOptions]`, живая проверка через `SCShareableContent.current`. `lostAfterUpdate` = разрешение было на прошлом `CFBundleVersion`, а сейчас нет. Кнопка «Сбросить запись» запускает `tccutil reset ScreenCapture com.bufr.app` для «залипших» ad-hoc записей. Deep links в Конфиденциальность → Запись экрана / Универсальный доступ / Клавиатура (проверить на macOS 26).
- **AppActivation.present(window)** и **SettingsWindowController.show(tab:)** заменяют [ClipPanelView.swift:353-378](Sources/Views/PanelWindow/ClipPanelView.swift#L353-L378), `AppState.openSettingsWindow` и `openSettings()` в MenuBarView.
- `Package.swift`: добавить `.testTarget(BufrTests)`. `Info.plist`: `LSMinimumSystemVersion` → 26.0 (сейчас 14.0, а таргет пакета — .v26). Usage-строки не нужны.

### M1 — Захват
**CaptureSessionController**, конечный автомат `idle → preparing → selecting(area|window) → adjusting(all-in-one) → finishing`:
1. Повторное нажатие хоткея во время сессии её отменяет. Прячем панель и превью. При запуске из меню строки меню ждём 200 мс.
2. Нет разрешения → `PermissionGuideView`, стоп.
3. Запоминаем frontmost app: это источник снимка, и ему потом вернём фокус.
4. Снимок состояния: `SCShareableContent` + `CGWindowListCopyWindowInfo` (front-to-back, слой 0, без нашего PID, без окон меньше 40pt).
5. Freeze-кадр на каждый `SCDisplay`: `SCContentFilter(display:excludingWindows:)` исключает наши окна из `CaptureExclusionRegistry` (панель, превью, Quick Access, тосты; закреплённые снимки **не** исключаем), `showsCursor = false`. Watchdog 3 с.
6. `CaptureOverlayWindow` на каждый `NSScreen`: NSPanel borderless, `.screenSaver`, `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, frame = `screen.frame`. Хоткеи и OCR-индексатор на паузе.
7. Ждём результат через `CheckedContinuation<CaptureOutcome?, Never>`. Потом teardown: освобождаем кадры (60–80 МБ на 5K), снимаем паузы, возвращаем фокус.
8. Отмена: Esc, `didResignActive`, `didChangeScreenParameters`, watchdog, повторный хоткей.

**CaptureOverlayView** (`isFlipped`, на слоях): замороженный кадр, затемнение (even-odd), рамка выделения + 8 ручек в режиме all-in-one, подсветка окна, плашка «W × H px», `LoupeLayer` (15×15 px ×8, nearest-neighbour, координаты и hex). Все обновления в `CATransaction.setDisableActions(true)`.

**Взаимодействие** (математика в чистом `SelectionGeometry`):
- Тянем мышью — новая область. ⇧ — квадрат, ⌥ — от центра, зажатый Space двигает область. Отпускание мыши = снимок (если протянули ≥ 4pt).
- Space до начала выделения переключает режим окна: наведение подсвечивает `WindowPicker.window(at:)`, клик снимает окно, ⌥-клик инвертирует тень.
- Return без выделения снимает прошлую область.
- All-in-one: область остаётся редактируемой (ручки, стрелки 1px, ⇧ 10px, ⌥+стрелки меняют размер), Return — снимок. Тулбар режимов на SwiftUI.

**ScreenGeometry** (чистые функции, покрыты тестами):
- `H = NSScreen.screens[0].frame.height` (**не** `NSScreen.main`). Cocoa→CG: `(x, H−(y+h), w, h)`.
- Локальные координаты оверлея → CG = `CGDisplayBounds(id).origin + local`.
- Точки→пиксели: `s = freeze.width / CGDisplayBounds.width`, по краям floor/ceil, результат обрезается границами изображения.
- Дисплей сопоставляем через `NSScreenNumber` == `SCDisplay.displayID`. Прошлую область храним по `CGDisplayCreateUUIDFromDisplayID`.

**Режимы → источник изображения** (`ScreenCaptureService`): область/текст — кроп кадра. Окно — `desktopIndependentWindow`, `ignoreShadows = !windowShadow`, `includeChildWindows`. Экран — фильтр дисплея под курсором, без оверлея. Прошлая область — фильтр дисплея + `config.sourceRect`, без оверлея.

**Постобработка** (`ScreenshotService.handle`), сначала обратная связь, потом диск:
1. Звук затвора (`/System/Library/.../Screen Capture.aif`).
2. Заранее создаём `itemId`, миниатюру из CGImage, **сразу** показываем Quick Access (или выполняем выбранное действие после снимка).
3. Вне главного потока: PNG с DPI = 72×scale (опционально уменьшение до 1x).
4. `clipIngestor.ingestImage(origin: .screenshot, deduplicate: false)`.
5. `ScreenshotFileWriter`: `copyItem` в папку (на APFS это клон), 0644, имя вида `"Снимок экрана 2026-09-23 в 14.05.12.png"` (префикс и связка локализованы, цифры POSIX, при коллизии « (2)»). Если папка недоступна — fallback + тост.
6. Если включено «копировать в буфер» (по умолчанию да) — `PasteboardWriter.writeImage` с маркером.
7. Сохраняем прошлую область (только для area/all-in-one).

### M2 — Quick Access Overlay + ScreenPin
- **QuickAccessPanel**: non-activating NSPanel, `.statusBar`, все Spaces, внесён в exclusion registry. Угол: снизу слева (по умолчанию) или справа от `visibleFrame`. Стек: новые сверху, максимум 5, остальные сворачиваются в «+N».
- **Карточка**: при наведении — Копировать / Сохранить как… / Аннотировать / Закрепить / Скопировать текст / Показать в Finder / ×. Свайп закрывает. **Drag-out** через `NSItemProvider.registerFileRepresentation(.png)` из `savedFilePath`; после успешного drop карточка закрывается. Автозакрытие 0/5/**10**/30/60 с, при наведении таймер на паузе. Закрытие ничего не удаляет.
- **ScreenPinPanel**: `[.nonactivatingPanel, .borderless, .resizable]`, `.floating`, `contentAspectRatio`, двигается за фон. Начальная рамка = место исходного снимка. Скролл меняет прозрачность 20–100%, стрелки двигают, Esc/⌘W закрывают, ⌘C копирует, двойной клик открывает редактор, L — Lock (`ignoresMouseEvents`, разблокировка из меню строки меню). Контекстное меню: Копировать / Сохранить как / Аннотировать / Прозрачность ▸ / Lock / Сбросить размер / Закрыть / Закрыть все. После правки вызываем `refresh(itemId:)`. Закрепления между перезапусками не сохраняются.
- Попутно: `ClipImageTransferable` (правильный drag с карточек), `ClipCardContextMenu`, исправление копирования в меню строки меню.

### M3 — OCR
- **OCRService** (Sendable):
  - `recognizeForIndex` — `RecognizeTextRequest` `.accurate`, языки из настроек (по умолчанию ru+en), `automaticallyDetectsLanguage`, порядок строк восстанавливает `OCRTextAssembler`.
  - `recognizeForCapture` — `RecognizeDocumentsRequest` (macOS 26): абзацы + штрихкоды/QR + URL. Если пусто — fallback.
- **Узбекский**: список языков берём в рантайме из `supportedRecognitionLanguages`. Латиница, скорее всего, работает через латинские модели, кириллица (ў қ ғ ҳ) под вопросом — нужен QA-набор.
- **Capture Text (⌘⇧2)**: тот же оверлей с бейджем «Aa» → кроп → распознавание → `PasteboardWriter.writeText` → `ingestText(origin: .textCapture)` → тост «Скопировано 124 символа» (для URL — кнопка «Открыть», если пусто — «Текст не найден»). В папку ничего не сохраняем.
- **OCRIndexer** (actor):
  - Очередь: `enqueue(id)` ставит новые картинки в начало, backfill выбирает через частичный индекс.
  - Режим: `Task(priority: .background)`, 250 мс между картинками, downsample до ≤ 6144 px, `autoreleasepool`. Результат пишется в `ocr_text` (пустой текст → `""`).
  - Пауза: во время захвата, в Low Power, при thermal ≥ serious, если настройка выключена.
  - `recognizeNow(id:)` для «Скопировать текст» и `pendingCount()` для настроек.
- Где используется: карточка («Скопировать текст»), Quick Access, выдвижная панель «Распознанный текст» в QuickPreview, поиск в панели.

### M4 — Редактор аннотаций
- **Модель** (`Codable, Sendable, Equatable`):
  - `AnnotationDocument { version, baseImageFilename, pixelWidth/Height, pointScale, crop: CGRect?, annotations }`.
  - `Annotation { id, kind, style }`.
  - Виды: arrow, line, rectangle, filledRectangle, ellipse, text, highlighter, pencil, counter, pixelate, blur, spotlight.
  - Вся геометрия в пикселях базового изображения, начало координат сверху слева. Golden JSON fixture в тестах.
- **Рендер**:
  - Порядок: база → эффекты (pixelate/blur только из **базовых** пикселей, CoreImage `CIPixellate`/`CIGaussianBlur`, один `CIContext`, кэш патчей) → spotlight (even-odd, 50%) → векторные объекты.
  - Хелпер `drawImageTopLeft` защищает от перевёрнутого изображения (закреплено тестом).
  - Стрелка — сужающийся полигон, маркер — `.multiply` с α 0.4, карандаш — Catmull-Rom, счётчик — круг с номером max+1.
- **Холст** `AnnotationCanvasView: NSView`:
  - `isFlipped`; bounds = пиксели, frame = пиксели / pointScale, поэтому события приходят уже в пикселях.
  - `NSScrollView.allowsMagnification`; база лежит в `layer.contents` и не перерисовывается.
  - `CanvasInteraction`: idle / creating / moving / resizing / editingText, ⇧ ограничивает углы 45° и делает квадраты. Текст редактируется в оверлее `NSTextView`.
- **Горячие клавиши**:
  - Инструменты: V выбор, A стрелка, L линия, R прямоугольник, F заливка, O эллипс, T текст, H маркер, P карандаш, N счётчик, X пикселизация, B размытие, S spotlight, C кроп.
  - Правка: ⌫ удалить, ⌘D дублировать, стрелки двигают, `[`/`]` толщина, 1–8 цвет, ⌘Z/⇧⌘Z undo/redo (NSUndoManager со снапшотами документа, один снапшот на жест).
  - Документ: ⌘C копирует результат, ⌘S сохранить, ⇧⌘S сохранить как, ⌘↩ готово.
- **Окно**: `EditorWindowController` (titled/resizable, ≤ 80% экрана, минимум 640×480), показывается через `AppActivation.present`, одно окно на item. При закрытии с изменениями — лист «Сохранить / Не сохранять / Отмена». Последний стиль каждого инструмента запоминается.
- **AnnotationStore.commit**:
  1. При первой правке `<u>.png` → `<u>_orig.png`.
  2. JSON атомарно.
  3. Рендер вне главного потока → `replaceImage` (файл + миниатюра + сброс кэша).
  4. Атомарно перезаписываем `savedFilePath`.
  5. БД: `annotationPath`, новый `hash`, размер, `createdAt = now`, `ocrText = NULL` (перезапуск OCR).
  6. `touch`, обновить закрепления и Quick Access.
- Ещё: `revert(item)` возвращает оригинал; «Сплющить и удалить слои» нужно для приватности (иначе оригинал под пикселизацией остаётся в App Support). Редактор открывается для **любых** картинок из истории. `ImageCardContent` перезагружается по `.task(id: item.hash)`.

### Интеграция в UI (M1–M5)
- **Панель** ([ClipPanelView.swift](Sources/Views/PanelWindow/ClipPanelView.swift)):
  - `PanelSource { history, screenshots, board(UUID) }`; вкладка «Скриншоты» (`camera.viewfinder`) сразу после «Буфер».
  - Табы выносим в `PanelTabsView`, файл сократится примерно с 687 до 450 строк. `onChange(of: items.map(\.id))`.
  - Пустое состояние: «Скриншотов пока нет — нажмите ⌘⇧4» (с реальным хоткеем).
- **Карточка**: бейдж скриншота, в подвале «2880 × 1800» + значок текста, если есть OCR. Контекстное меню картинок: Аннотировать / Закрепить / Скопировать текст / Показать в Finder / Сохранить как / Вернуть оригинал.
- **QuickPreview**: те же кнопки + выдвижная панель с распознанным текстом.
- **Меню строки меню**: Снимок области ⌘⇧4, Окна, Экрана ⌘⇧3, Прошлой области, Все режимы… ⌘⇧5, Распознать текст ⌘⇧2, Открыть папку скриншотов, «Закреплённые ▸ Разблокировать все / Закрыть все» (если есть), «⚠︎ Нужно разрешение…» (если нет), затем существующие пункты. Сочетания строятся из текущих привязок.
- **Настройки** (`SettingsTab` + `.screenshots`, `.permissions`):
  - *Скриншоты*: папка (выбор / показать / сброс), префикс имени с превью, действие после снимка (Quick Access / Редактор / Закрепить / Ничего), копировать в буфер, звук, позиция и автозакрытие Quick Access, курсор, тень окна, Retina → 1x, лупа; OCR (вкл/выкл, «Проиндексировано X из Y», переиндексировать, очистить, языки).
  - *Горячие клавиши*: группы «Панель» / «Скриншоты» с `HotKeyRecorderView` (live-модификаторы, Esc — отмена, ⌫ — отключить, минимум один из ⌘⌃⌥, конфликты прямо в строке), сброс строки и всех. `SystemShortcutsBanner` с пошаговой инструкцией и кнопкой «Открыть настройки клавиатуры», статус обновляется вживую.
  - *Разрешения*: Запись экрана (статус / выдать / открыть настройки / сбросить запись / перезапустить) и Универсальный доступ (нужен для вставки). Пояснение про ad-hoc.
- **Онбординг**:
  - `ScreenshotSetupView` при первом запуске v3 — 3 шага с живыми галочками: разрешение → отключить системные хоткеи → папка.
  - `PermissionGuideView`, если снимок запускают без разрешения (варианты: не спрашивали / отказано / потеряно после обновления).
  - Тост после обновления, если разрешение слетело.

### Локализация
Около 180 новых ключей × ru/en/uz в `Sources/Resources/*.lproj/Localizable.strings`, через `L10n()`. Семейства ключей: `capture.*`, `screenshot.*`, `quickAccess.*`, `screenPin.*`, `ocr.*`, `editor.*`, `permissions.*`, `setup.*`, `hotkeys.action.*`, `menubar.capture.*`, `toast.*`, `panel.screenshots*`, `card.*`. Узбекский нужно вычитать носителю.

---

## Этапы (одна ветка `feature/screenshots`, один релиз 3.0.0)
После каждого этапа: `swift build` + `swift test` + `./scripts/build-app.sh debug && open Bufr.app`.

| Этап | Содержимое | Готово, когда |
|---|---|---|
| **M0** Фундамент | test target, Info.plist 26.0, AppPaths, ImageStorage, ClipOrigin, поля ClipItem, миграция v4, API ClipItemStore, ClipIngestor, PasteboardWriter, рефакторинг monitor/paster (баги 1–4), HotKeyBinding/Manager + миграция хоткея + рекордер, SystemShortcutInspector, PermissionsManager, AppActivation, SettingsWindowController, поля экспорта (SystemShortcutInspector, PermissionsManager и AppRelauncher перенесены в M1 — к первому потребителю) | Приложение ведёт себя как раньше; вставка картинки не плодит дубли; ⌘⇧V работает после обновления |
| **M1** Захват | Capture/*, Screenshots/*, хоткеи захвата с учётом конфликтов, PermissionGuide, базовые настройки, баннер хоткеев, вкладка «Скриншоты», пункты меню | ⌘⇧3 / ⌘⇧4 (+Space) / прошлая область → PNG в `~/Pictures/Bufr` + карточка + буфер без дубля |
| **M2** Quick Access, Pin, ⌘⇧5 | QuickAccess/*, ScreenPin/*, Toast, действие после снимка, AllInOneToolbar, drag с карточек, контекстное меню | Снимки стекаются в углу, drag-out в Finder/Telegram/Slack, закрепления: lock и прозрачность |
| **M3** OCR | OCR/*, ⌘⇧2 + QR/URL, backfill, настройки OCR, «Скопировать текст» | Поиск по словам внутри старых картинок работает; ⌘⇧2 копирует текст |
| **M4** Редактор | Editor/*, commit/revert/flatten, все точки входа | Правка → карточка и файл в папке обновились; повторное открытие позволяет двигать стрелки; undo/redo работает |
| **M5** Полировка | вкладка «Разрешения», ScreenshotSetup, полные настройки, финальное меню, вся локализация, производительность (хоткей → оверлей < 250 мс; отпускание мыши → Quick Access < 150 мс), память, `3.0.0`/`CFBundleVersion 30`, обновление CLAUDE.md | Пройден ручной QA-чек-лист |

---

## Проверка

**Юнит-тесты** (`Tests/BufrTests`, Swift Testing, `swift test`):
- `ScreenGeometryTests`: второй дисплей сверху и слева (отрицательные координаты), floor/ceil пикселей, дробный масштаб.
- `SelectionGeometryTests`, `WindowPickerTests`, `ScreenshotFilenameFormatterTests` (фиксированные дата и TZ, коллизии).
- `SystemShortcutInspectorTests`: фикстуры включён / выключен / **отсутствует = включён** / переназначен.
- `HotKeyBindingTests`: JSON, миграция старых ключей на изолированном `UserDefaults(suiteName:)`, дубли, конфликты.
- `DatabaseMigrationTests`: `migrate(upTo: v3)` → старые строки → v4 → FTS находит старый текст; `ocr_text = "Привет мир"` → `search("прив")` находит; фильтр по origin.
- `ClipIngestorTests`: UUID файла == item.id; при дедупликации файл не пишется; TIFF → настоящий PNG (magic bytes).
- `ClipboardMonitorTests` на именованном pasteboard: маркер игнорируется.
- `AnnotationDocumentTests` (golden JSON), `AnnotationRendererTests`: красный прямоугольник в известных пикселях ловит баг с переворотом; пикселизация — однородные блоки; рендер детерминирован.
- `OCRTextAssemblerTests`, `ExportCompatibilityTests` (старый `.bufr` декодируется), `LocalizationTests` (ключи ru/en/uz совпадают, все `L10n("…")` существуют).

**Ручная проверка** (только на собранном `.app`: у голого бинарника TCC приписывается Терминалу):
- **Дисплеи и пространства**: Retina + внешний не-Retina, второй дисплей сверху и слева, режим «Больше места», вырез, полноэкранное приложение, Stage Manager, ⌘Tab во время захвата (сессия должна отмениться), захват из меню строки меню (меню не попадает в кадр).
- **Хоткеи и разрешения**: хоткеи при включённых системных (показано «занято», двойного снимка нет) и после их отключения; разрешения — первый запуск / отказ / отзыв / после ad-hoc обновления.
- **Снимки и перенос**: DPI 144 в Инспекторе Preview; drag-out в Finder, Telegram, Mail; закрепления на разных Spaces.
- **OCR**: ru / en / узбекский (латиница и кириллица) / код / QR; backfill 1000 картинок под наблюдением CPU.
- **Редактор и память**: изображение 6K при 60 fps; после пикселизации в экспорте нет исходных пикселей; revert; Instruments на 20 захватов.

---

## Риски
- **TCC + ad-hoc**: после обновления разрешение сбрасывается, а переключатель остаётся «включён» у старой записи. Закрываем детектом `lostAfterUpdate`, кнопками «сбросить запись» и «перезапустить» и понятным объяснением. *Необязательная рекомендация на будущее:* бесплатный самоподписанный сертификат вместо ad-hoc — тогда разрешения переживают обновления. В этот план не входит, решение за вами. Для разработки добавим в `build-app.sh` переменную `BUFR_SIGN_IDENTITY` (по умолчанию `-`), это поведение релиза не меняет.
- **Периодический системный запрос согласия ScreenCaptureKit**: вызовы SCK идут до оверлея, плюс watchdog 3 с.
- **Swift 6 strict concurrency**: SCK-типы не Sendable, поэтому держим их на `@MainActor` с `@preconcurrency import`. Между акторами передаём только CGImage / Data / value-типы.
- **Память**: freeze-кадры освобождаем в teardown, лупа работает на zero-copy `cropping`, у OCR есть `autoreleasepool`.
- **Хоткеи**: регистрация Carbon молча падает при конфликте, поэтому регистрируем с учётом конфликтов (D12).
- **Приватность**: OCR-текст хранится в локальной БД (как и сейчас текст буфера), для оригиналов есть «Сплющить слои» и «Очистить распознанный текст».

## Вне рамок v1 (куда потом встраивать)
- Запись экрана/GIF: `SCStream` + `SCRecordingOutput` на том же оверлее.
- Скроллинг-захват: повторные `sourceRect` + склейка.
- Таймер: `delay` в меню ⌘⇧5.
- Background tool: поле `background` в `AnnotationDocument` (у формата есть version).
- Прочее: облако, сохранение закреплений между запусками, выделение через несколько дисплеев, JPEG/HEIC, HDR.

## Следующий шаг после одобрения
1. Сохранить этот дизайн как спецификацию `docs/superpowers/specs/2026-09-23-screenshots-design.md`.
2. Через writing-plans разбить M0–M5 на пошаговые задачи с тестами.
3. Выполнять по этапам в ветке `feature/screenshots`.
