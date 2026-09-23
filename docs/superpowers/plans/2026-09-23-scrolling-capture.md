# Скроллинг-захват — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Длинный скриншот прокручиваемой области: выделение, живой захват с ручной и авто-прокруткой, склейка, результат через обычный путь скриншотов.

**Architecture:**
- **Склейка** — чистый модуль `ScrollStitcher` над RGBA-буферами (без UI и ScreenCaptureKit), покрыт синтетическими тестами.
- **Кадры** — `SCStream` по области, без окон Bufr.
- **`ScrollingCaptureSession`** связывает источник кадров, склейку, авто-прокрутку и две панели (рамка и управление).
- **Результат** — обычный `CaptureOutcome` → `ScreenshotCoordinator.process`.
- **Распознавание длинных картинок** — по полосам.

**Tech Stack:** Swift 6.2 (Swift 6 mode), SwiftUI + AppKit, ScreenCaptureKit (`SCStream`), CoreGraphics / CoreImage, Carbon-хоткеи (HotKey), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-23-scrolling-capture-design.md` (основная спецификация 3.0 — `2026-09-23-screenshots-design.md`).

## Global Constraints
- Выпуск в составе 3.0.0, версия и `CFBundleVersion` не меняются.
- Работа в `main`, без пуша; коммиты на русском через `git commit -F`, в конце `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- macOS 26+, строгая конкурентность Swift 6; типы ScreenCaptureKit держим на `@MainActor` с `@preconcurrency import`.
- Окна Bufr никогда не попадают в кадры (`excludingApplications: [Bufr]`).
- Хоткей по умолчанию `captureScrolling` = ⌥⇧⌘4 (переназначаемый, с проверкой конфликтов, как остальные).
- Растёт только вниз. Предел — 30 000 px высоты или 60 Мп.
- «Авто»: шаг — половина высоты области, конец страницы — 3 шага подряд без сдвига.
- Длинные картинки распознаются полосами: > 6144 px и > 2× ширины → полосы 4096 px с перекрытием 200 px.
- Строки — ru/en/uz через `L10n`; все ключи в трёх файлах (`LocalizationTests`).
- Тесты не трогают реальные данные Bufr, окна в тестах создаются с `isReleasedWhenClosed = false`, `#expect` без голых `nil`-аргументов (медленная проверка типов).

## Review Focus
1. **Прилипающая шапка и белые поля страницы.** Строки полей совпадают «случайно», но склейка не должна ни дублировать содержимое, ни терять его. Тест `ScrollStitcherTests.whiteMarginsAndStickyHeaderStitchExactly` (Task 1).
2. **Конец страницы в режиме «Авто».** `SCStream` не присылает новых кадров, когда картинка не меняется, поэтому отсутствие кадра после прокрутки считается «без сдвига», и авто останавливается. Тест `ScrollingCaptureSessionTests.autoStopsAtTheEndWhenNoFramesArrive` (Task 6).
3. **Быстрая ручная прокрутка без перекрытия.** Холст не портится, склейка продолжается со следующего нормального кадра. Тест `ScrollStitcherTests.lostTrackKeepsTheCanvasAndRecovers` (Task 1).
4. **Второй дисплей с другим масштабом.** Пиксельный размер кадров = точки × масштаб именно этого дисплея, а `pointScale` результата с ним совпадает. Тест `ScrollRegionTests.pixelSizeUsesTheRegionsDisplayScale` (Task 4).
5. **Результат у предела и поиск по нему.** Захват останавливается на пределе, сборка работает, текст внизу длинной картинки находится. Тесты `ScrollStitcherTests.stopsAtTheHeightLimit` (Task 1) и `OCRTilingTests.bottomOfATallImageIsRecognized` (Task 2).

---

### Task 1: `ScrollStitcher` — склейка

**Files:**
- Create: `Sources/Capture/Scrolling/ScrollStitcher.swift`, `Sources/Capture/Scrolling/RGBABuffer.swift`
- Test: `Tests/BufrTests/ScrollStitcherTests.swift`, `Tests/BufrTests/Support/ScrollPages.swift`

**Interfaces:**
- Produces:
  - `struct RGBABuffer { let width: Int; let height: Int; var bytes: [UInt8]; init?(_ image: CGImage); func rows(_ range: Range<Int>) -> ArraySlice<UInt8>; func makeImage() -> CGImage? }` — sRGB, 8 бит, premultipliedLast.
  - `final class ScrollStitcher`:
    - `init(firstFrame: CGImage, maxHeight: Int = 30_000, maxPixels: Int = 60_000_000)`;
    - `enum Step: Equatable { case added(Int), noMovement, movedUp, lostTrack, limitReached }`;
    - `func append(_ frame: CGImage) -> Step`;
    - `var width: Int`, `var height: Int` (высота результата, если собрать сейчас);
    - `func compose() -> CGImage?`;
    - `func preview(maxWidth: Int) -> CGImage?`.

**Алгоритм** (из спецификации, раздел «Склейка»):
- **Подпись кадра.** Для каждой строки 64 значения средней яркости по колонкам-корзинам. Строки сравниваются по средней абсолютной разности (MAD).
- **Состояние:**
  - `committed` — `RGBABuffer` растущей высоты;
  - `last` — последний кадр и его подпись;
  - `bottomRow` — строка последнего кадра, до которой содержимое уже в `committed`;
  - `firstPending` — первый кадр ждёт первого сдвига, чтобы узнать подвал.
- **Прилипающие полосы:** H — ведущие, F — хвостовые строки, совпадающие с прошлым кадром (MAD ≤ 2). Если `H + F ≥ h − minBand` (где `minBand` = h/4), результат `.noMovement`.
- **Сдвиг.** Полоса `[H, h−F)`, перекрытие не меньше 25% полосы:
  - грубый поиск по одномерному профилю (средняя яркость строки) для всех `d` в `±(band − minOverlap)`;
  - 5 лучших кандидатов проверяются по полной подписи;
  - `d` принимается, если MAD ≤ 3 и он лучший; при равенстве в пределах 0,5 берётся ближайший к прошлому сдвигу;
  - `d > 0` — дописываем, `d < 0` — `.movedUp`, ничего не подошло — `.lostTrack`.
- **Дописывание:**
  - первый сдвиг: `committed` = строки первого кадра `[0, h−F)`, `bottomRow = h−F−d` в координатах нового кадра;
  - дальше: новые строки `[bottomRow − d, h − F)` нового кадра дописываются в `committed`, затем `bottomRow = h − F`.
- **Сборка:** `committed` + строки `[bottomRow, h)` последнего кадра (подвал и недописанный хвост). Если сдвига не было, результат — первый кадр целиком.
- **Предел:** дописывается только то, что влезает, дальше `.limitReached` (и все последующие `append` тоже).

- [ ] **Step 1: Синтетические страницы для тестов** (`Support/ScrollPages.swift`)

```swift
import CoreGraphics
@testable import Bufr

/// Tall test "pages" with rows that never repeat (seeded), cut into frames like a scrolled view.
enum ScrollPages {
    static func page(width: Int = 240, height: Int = 3000, seed: UInt64 = 1, whiteBands: Bool = false) -> CGImage {
        var rng = SeededGenerator(seed: seed)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var y = 0
        while y < height {
            let blockHeight = Int.random(in: 6...40, using: &rng)
            if whiteBands && Int.random(in: 0..<4, using: &rng) == 0 {
                y += blockHeight * 3 // blank stretch, like page margins between paragraphs
                continue
            }
            for _ in 0..<Int.random(in: 1...4, using: &rng) {
                let x = Int.random(in: 0..<(width - 20), using: &rng)
                let w = Int.random(in: 10...(width - x), using: &rng)
                context.setFillColor(CGColor(gray: CGFloat.random(in: 0...0.85, using: &rng), alpha: 1))
                context.fill(CGRect(x: x, y: height - y - blockHeight, width: w, height: blockHeight))
            }
            y += blockHeight
        }
        return context.makeImage()!
    }

    /// The viewport at `offset` (top-left origin), optionally with a fixed header/footer painted over it.
    static func frame(of page: CGImage, offset: Int, height: Int, header: Int = 0, footer: Int = 0) -> CGImage {
        let crop = page.cropping(to: CGRect(x: 0, y: offset, width: page.width, height: height))!
        let context = CGContext(data: nil, width: page.width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(crop, in: CGRect(x: 0, y: 0, width: page.width, height: height))
        if header > 0 {
            context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: height - header, width: page.width, height: header))
        }
        if footer > 0 {
            context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: page.width, height: footer))
        }
        return context.makeImage()!
    }

    static func sameRGBA(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height, let x = RGBABuffer(a), let y = RGBABuffer(b) else { return false }
        return x.bytes == y.bytes
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
```

- [ ] **Step 2: Написать падающие тесты** (`ScrollStitcherTests.swift`)

```swift
import CoreGraphics
import Testing
@testable import Bufr

struct ScrollStitcherTests {
    private func stitch(_ page: CGImage, offsets: [Int], height: Int = 400, header: Int = 0, footer: Int = 0) -> (ScrollStitcher, [ScrollStitcher.Step]) {
        let frames = offsets.map { ScrollPages.frame(of: page, offset: $0, height: height, header: header, footer: footer) }
        let stitcher = ScrollStitcher(firstFrame: frames[0])
        let steps = frames.dropFirst().map { stitcher.append($0) }
        return (stitcher, steps)
    }

    @Test func steadyScrollRebuildsThePage() throws {
        let page = ScrollPages.page()
        let (stitcher, steps) = stitch(page, offsets: Array(stride(from: 0, through: 1500, by: 100)))
        let result = try #require(stitcher.compose())
        let expected = try #require(page.cropping(to: CGRect(x: 0, y: 0, width: page.width, height: 1900)))

        #expect(steps.allSatisfy { $0 == .added(100) })
        #expect(ScrollPages.sameRGBA(result, expected))
    }

    @Test func unevenStepsRebuildThePage() throws {
        let page = ScrollPages.page(seed: 2)
        let (stitcher, _) = stitch(page, offsets: [0, 37, 210, 211, 480, 650, 900])
        let result = try #require(stitcher.compose())
        let expected = try #require(page.cropping(to: CGRect(x: 0, y: 0, width: page.width, height: 1300)))

        #expect(ScrollPages.sameRGBA(result, expected))
    }

    @Test func stickyHeaderAndFooterAppearOnce() throws {
        let page = ScrollPages.page(seed: 3)
        let offsets = Array(stride(from: 0, through: 1200, by: 150))
        let (stitcher, _) = stitch(page, offsets: offsets, header: 40, footer: 30)
        let result = try #require(stitcher.compose())

        #expect(result.height == 400 + 1200) // header + scrolled content + footer, each once
        let top = try #require(ScrollPages.frame(of: page, offset: 0, height: 400, header: 40, footer: 30).cropping(to: CGRect(x: 0, y: 0, width: page.width, height: 370)))
        #expect(ScrollPages.sameRGBA(try #require(result.cropping(to: CGRect(x: 0, y: 0, width: page.width, height: 370))), top))
        let bottom = try #require(ScrollPages.frame(of: page, offset: 1200, height: 400, header: 40, footer: 30).cropping(to: CGRect(x: 0, y: 40, width: page.width, height: 360)))
        #expect(ScrollPages.sameRGBA(try #require(result.cropping(to: CGRect(x: 0, y: 1240, width: page.width, height: 360))), bottom))
    }

    /// Review Focus 1: blank margins match "by accident" at the same height in two frames.
    @Test func whiteMarginsAndStickyHeaderStitchExactly() throws {
        let page = ScrollPages.page(seed: 4, whiteBands: true)
        let offsets = Array(stride(from: 0, through: 1600, by: 120))
        let (stitcher, _) = stitch(page, offsets: offsets, header: 40)
        let result = try #require(stitcher.compose())
        let expectedBody = try #require(page.cropping(to: CGRect(x: 0, y: 40, width: page.width, height: 1960)))

        #expect(result.height == 2000)
        #expect(ScrollPages.sameRGBA(try #require(result.cropping(to: CGRect(x: 0, y: 40, width: page.width, height: 1960))), expectedBody))
    }

    @Test func scrollingUpIsIgnored() {
        let page = ScrollPages.page(seed: 5)
        let (stitcher, steps) = stitch(page, offsets: [0, 200, 100, 300])

        #expect(steps == [.added(200), .movedUp, .added(100)])
        #expect(stitcher.height == 700)
    }

    /// Review Focus 3
    @Test func lostTrackKeepsTheCanvasAndRecovers() throws {
        let page = ScrollPages.page(seed: 6)
        let (stitcher, steps) = stitch(page, offsets: [0, 100, 900, 200, 300])
        let result = try #require(stitcher.compose())
        let expected = try #require(page.cropping(to: CGRect(x: 0, y: 0, width: page.width, height: 700)))

        #expect(steps == [.added(100), .lostTrack, .added(100), .added(100)])
        #expect(ScrollPages.sameRGBA(result, expected))
    }

    @Test func sameFrameIsNoMovement() {
        let page = ScrollPages.page(seed: 7)
        let (_, steps) = stitch(page, offsets: [0, 0])

        #expect(steps == [.noMovement])
    }

    /// Review Focus 5
    @Test func stopsAtTheHeightLimit() throws {
        let page = ScrollPages.page(seed: 8)
        let frames = [0, 300, 600, 900].map { ScrollPages.frame(of: page, offset: $0, height: 400) }
        let stitcher = ScrollStitcher(firstFrame: frames[0], maxHeight: 1000)
        let steps = frames.dropFirst().map { stitcher.append($0) }

        #expect(steps == [.added(300), .added(300), .limitReached])
        #expect(try #require(stitcher.compose()).height == 1000)
    }
}
```

- [ ] **Step 3: Запустить** — `swift build --build-tests && swift test --skip-build --filter ScrollStitcherTests`. Ожидается: сборка падает, `ScrollStitcher` / `RGBABuffer` не найдены.
- [ ] **Step 4: Реализовать** `RGBABuffer` и `ScrollStitcher` по алгоритму выше.
- [ ] **Step 5: Запустить** тот же фильтр. Ожидается: 8/8 PASS.
- [ ] **Step 6: Коммит** — `feat: склейка кадров для скроллинг-захвата`.

---

### Task 2: Распознавание длинных картинок полосами

**Files:**
- Create: `Sources/OCR/OCRTiling.swift`
- Modify: `Sources/OCR/OCRIndexer.swift` (`recognizeAndStore`, `loadImage`)
- Test: `Tests/BufrTests/OCRTilingTests.swift`

**Interfaces:**
- Produces:
  - `enum OCRTiling`:
    - `static func tiles(width: Int, height: Int, maxSide: Int = 6144, tileHeight: Int = 4096, overlap: Int = 200) -> [CGRect]` — одна полоса, если `height ≤ maxSide` или `height < 2 × width`;
    - `static func join(_ texts: [String], overlapLines: Int = 6) -> String` — выбрасывает в начале следующей полосы строки, повторяющие конец предыдущей.
- `OCRIndexer`: длинная картинка грузится целиком (`CGImageSourceCreateImageAtIndex`); каждая полоса вырезается, при ширине больше 6144 px уменьшается и распознаётся через `recognize`; тексты склеиваются через `join`.

- [ ] **Step 1: Тесты:**
  - `tilesCoverATallImageWithOverlap` — 800×9000 → `[0..4096, 3896..7992, 7792..9000]`;
  - `shortOrWideImageIsOneTile` — 3000×2000 и 1000×6000;
  - `joinDropsLinesRepeatedAtTheSeam` — `["a\nb\nc", "b\nc\nd"]` → `"a\nb\nc\nd"`;
  - `tallImageIsRecognizedInTiles` — поддельный распознаватель получает 3 картинки высотой 4096/4096/1208;
  - `bottomOfATallImageIsRecognized` — настоящий Vision: 900×9000, «Top Alpha» наверху и «Bottom Omega» внизу, оба найдены.
- [ ] **Step 2: Запустить** — `swift test --skip-build --filter OCRTilingTests` (после `swift build --build-tests`). Ожидается: сборка падает, `OCRTiling` не найден.
- [ ] **Step 3: Реализовать.** Для картинок из одной полосы путь не меняется.
- [ ] **Step 4: Запустить.** Ожидается: 5/5 PASS, `OCRIndexerTests` зелёные.
- [ ] **Step 5: Коммит** — `feat: распознавание длинных картинок по частям`.

---

### Task 3: Авто-прокрутка

**Files:**
- Create: `Sources/Capture/Scrolling/AutoScroll.swift`
- Test: `Tests/BufrTests/AutoScrollPolicyTests.swift`

**Interfaces:**
- Produces:
  - `struct AutoScrollPolicy`:
    - `init(regionHeightPoints: CGFloat)`;
    - `var stepPoints: CGFloat` — начально высота/2;
    - `mutating func record(_ step: ScrollStitcher.Step) -> Decision`, где `enum Decision { case scrollAgain, reachedEnd, stop }`:
      - `.noMovement` 3 раза подряд → `.reachedEnd`;
      - `.added` сбрасывает счётчик;
      - `.lostTrack` уменьшает шаг вдвое, не ниже высота/8;
      - `.limitReached` → `.stop`;
      - `.movedUp` → `.scrollAgain`.
  - `@MainActor protocol AutoScrolling { var isAvailable: Bool { get }; func scroll(by points: CGFloat, at point: CGPoint) }`.
  - `@MainActor final class SystemAutoScroller: AutoScrolling`:
    - `isAvailable` = `AXIsProcessTrusted()`;
    - `scroll` при первом вызове переносит курсор в центр области (`CGWarpMouseCursorPosition`) и посылает `CGEvent(scrollWheelEvent2Source:units: .pixel, wheelCount: 1, wheel1: -Int32(points))` в `.cghidEventTap`.

- [ ] **Step 1: Тесты:**
  - `stepIsHalfTheRegion`;
  - `threeStillStepsMeanTheEnd`;
  - `movementResetsTheCount`;
  - `lostTrackHalvesTheStepDownToAnEighth`;
  - `limitStops`.
- [ ] **Step 2: Запустить** `--filter AutoScrollPolicyTests`. Ожидается: сборка падает (нет типов).
- [ ] **Step 3: Реализовать.**
- [ ] **Step 4: Запустить.** Ожидается: 5/5 PASS.
- [ ] **Step 5: Коммит** — `feat: авто-прокрутка для скроллинг-захвата`.

---

### Task 4: Точки входа и выбор области

**Files:**
- Modify:
  - `Sources/Capture/CaptureMode.swift` (`.scrolling`, `ScrollRegion`, `CaptureSessionResult`);
  - `Sources/Capture/CaptureSessionController.swift` (возвращает `CaptureSessionResult`; режим `.scrolling`; выбор окна → область; «Прокрутка» в ⇧⌘5);
  - `Sources/Capture/Overlay/AllInOneToolbar.swift` (кнопка «Прокрутка»);
  - `Sources/Models/HotKeyAction.swift` (`captureScrolling`, ⌥⇧⌘4);
  - `Sources/App/AppState.swift` (обработка);
  - `Sources/Views/MenuBar/MenuBarView.swift` (пункт меню);
  - `Sources/Screenshots/ScreenshotCoordinator.swift` (результат `.scrollRegion` → пока звук ошибки; сеанс подключается в Task 6);
  - `Localizable.strings` ×3.
- Test: `Tests/BufrTests/ScrollRegionTests.swift`, `Tests/BufrTests/HotKeyBindingTests.swift` (новый тест).

**Interfaces:**
- Produces:
  - `struct ScrollRegion: Equatable, Sendable`:
    - поля `displayID: CGDirectDisplayID`, `localRect: CGRect` (точки, начало сверху слева), `screenFrame: CGRect` (Cocoa), `pointScale: CGFloat`, `sourceAppId: String?`, `sourceAppName: String?`;
    - `var pixelSize: CGSize`;
    - `var cocoaRect: CGRect`;
    - `static func fromWindow(cgFrame: CGRect, screenFrame: CGRect, primaryHeight: CGFloat, ...) -> CGRect?` — область окна на его дисплее, обрезанная границами экрана.
  - `enum CaptureSessionResult { case image(CaptureOutcome), scrollRegion(ScrollRegion) }`; `CaptureSessionController.capture(_:options:) async throws -> CaptureSessionResult?`.
  - `CaptureSelection.scroll(displayID:localRect:)` — из панели ⇧⌘5.

- [ ] **Step 1: Тесты:**
  - `pixelSizeUsesTheRegionsDisplayScale` — 300×200 pt на дисплее ×2 → 600×400, на ×1 → 300×200;
  - `windowRegionIsClippedToItsScreen`;
  - `scrollingShortcutDefaultsToOptionShiftCommandFour` — привязка по умолчанию; с другими действиями не совпадает.
- [ ] **Step 2: Запустить.** Ожидается: сборка падает.
- [ ] **Step 3: Реализовать** типы, режим, кнопку, хоткей, пункт меню, строки.
- [ ] **Step 4: Запустить** новые тесты, `LocalizationTests`, `HotKeyBindingTests` и весь набор. Ожидается: всё зелёное.
- [ ] **Step 5: Коммит** — `feat: точки входа скроллинг-захвата`.

---

### Task 5: Источник кадров (`SCStream`)

**Files:**
- Create: `Sources/Capture/Scrolling/ScrollFrameSource.swift`
- Test: `Tests/BufrTests/ScrollFrameSourceTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor protocol ScrollFrameSource: AnyObject`:
    - `func start(onFrame: @escaping @MainActor (CGImage) -> Void) async throws`;
    - `func stop() async`.
  - `@MainActor final class StreamFrameSource: NSObject, ScrollFrameSource`:
    - `init(region: ScrollRegion)`;
    - `SCStream`: фильтр дисплея без окон Bufr, `sourceRect = region.localRect`, `width/height = region.pixelSize`, BGRA, `minimumFrameInterval = 1/12`, `showsCursor = false`, `queueDepth = 3`;
    - берутся только кадры `SCFrameStatus.complete`.
  - `enum FrameConversion { static func image(from pixelBuffer: CVPixelBuffer) -> CGImage? }` — копия в собственный буфер, чтобы не держать пул потока.

- [ ] **Step 1: Тест** `pixelBufferBecomesAnOwnedImage` — BGRA-буфер 4×2 с известными пикселями → `CGImage` с теми же RGBA; после изменения буфера картинка не меняется.
- [ ] **Step 2: Запустить.** Ожидается: сборка падает.
- [ ] **Step 3: Реализовать** (поток проверяется вручную, в Task 7).
- [ ] **Step 4: Запустить.** Ожидается: PASS.
- [ ] **Step 5: Коммит** — `feat: поток кадров для скроллинг-захвата`.

---

### Task 6: Сеанс, панели и подключение

**Files:**
- Create:
  - `Sources/Capture/Scrolling/ScrollingCaptureSession.swift`;
  - `Sources/Capture/Scrolling/ScrollingCapturePanels.swift` (рамка + панель управления + `ScrollingCaptureControls` на SwiftUI).
- Modify:
  - `Sources/Screenshots/ScreenshotCoordinator.swift` — `.scrollRegion` → сеанс → `CaptureOutcome` → `process` / `onCaptured`; повторный `.scrolling` во время сеанса = «Готово», другие режимы игнорируются;
  - `Sources/App/AppState.swift`.
- Test: `Tests/BufrTests/ScrollingCaptureSessionTests.swift`

**Interfaces:**
- Consumes:
  - `ScrollStitcher` (Task 1);
  - `AutoScrollPolicy`, `AutoScrolling` (Task 3);
  - `ScrollRegion` (Task 4);
  - `ScrollFrameSource` (Task 5).
- Produces:
  - `@MainActor @Observable final class ScrollingCaptureModel`:
    - `pixelSize: CGSize`, `preview: CGImage?`, `isAuto: Bool`;
    - `hint: Hint` (`.start`, `.slower`, `.end`, `.limit`, `.none`);
    - `autoUnavailable: Bool`.
  - `@MainActor final class ScrollingCaptureSession`:
    - `init(region: ScrollRegion, source: ScrollFrameSource, scroller: AutoScrolling, stillFrameTimeout: Duration = .milliseconds(450), maxHeight: Int = 30_000, showsPanels: Bool = true)`;
    - `func run() async -> CGImage?` — nil при отмене;
    - `func finish()`, `func cancel()`, `func toggleAuto()`;
    - `let model`.
  - Кадры склеиваются вне главного потока (`actor StitchWorker`). Пока идёт обработка, хранится только самый свежий кадр.
  - В режиме «Авто» после прокрутки ждём кадр до `stillFrameTimeout`; нет кадра → `.noMovement`.
  - Esc и Return на время сеанса — временные `HotKey`.

- [ ] **Step 1: Тесты** (поддельный источник выдаёт кадры синтетической страницы, поддельный скроллер сдвигает окно страницы):
  - `manualFramesAreStitchedAndFinishReturnsTheImage`;
  - `cancelReturnsNothing`;
  - `autoScrollsToTheEndAndStops` — страница 1600 px, область 400 px → поле `isAuto` выключилось, `hint == .end`, результат 1600 px;
  - `autoStopsAtTheEndWhenNoFramesArrive` — после конца источник кадров не шлёт (Review Focus 2);
  - `autoWithoutAccessibilityExplainsAndStaysManual`.
- [ ] **Step 2: Запустить.** Ожидается: сборка падает.
- [ ] **Step 3: Реализовать** сеанс, панели (`showsPanels: false` в тестах) и подключение в координаторе.
- [ ] **Step 4: Запустить** новые тесты и весь набор. Ожидается: всё зелёное.
- [ ] **Step 5: Коммит** — `feat: сеанс скроллинг-захвата`.

---

### Task 7: Документы и приёмка

**Files:** `docs/release-notes-3.0.md`, `docs/qa-3.0-checklist.md`, `CLAUDE.md` (строка про `Capture/Scrolling`).

- [ ] **Step 1: Заметки к выпуску.** Раздел «Скроллинг-захват»:
  - как запустить, режимы, «Авто»;
  - значок записи экрана во время захвата;
  - где склейка может ошибаться: анимированная прокрутка, параллакс, видео.
- [ ] **Step 2: Чек-лист** — пункты ручной проверки из спецификации.
- [ ] **Step 3: Приёмка:**
  - полный `swift test` (ожидается: всё зелёное);
  - `swift build -c release`;
  - `./scripts/build-app.sh debug` и запуск Bufr-Debug.
- [ ] **Step 4: Коммит** — `docs: скроллинг-захват в заметках к выпуску и чек-листе`.
- [ ] **Step 5: Итоговое ревью** всей ветки свежим ревьюером (opus), исправления с тестами, отчёт.
