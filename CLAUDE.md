# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Bufr is a free, open-source, native macOS clipboard manager built with Swift and SwiftUI. It aims to replicate the visual clipboard history experience of Paste (pasteapp.io) — horizontal card ribbon, pinboards, fuzzy search — while being completely free and privacy-focused (all data stored locally).

Since 3.0 it also takes CleanShot X–style screenshots (capture, Quick Access, pins, OCR, annotation editor); every capture becomes a history card. Design spec and per-milestone plans (Russian): `docs/superpowers/specs/2026-09-23-screenshots-design.md`, `docs/superpowers/plans/`.

## Tech Stack

- **Language:** Swift 6.2 tools, Swift 6 language mode (strict concurrency)
- **UI:** SwiftUI + AppKit (NSPanel overlays, NSPasteboard, custom NSView canvas)
- **Storage:** SQLite via GRDB.swift (with FTS5 for full-text search)
- **Package Manager:** Swift Package Manager; tests use Swift Testing (`Tests/BufrTests`)
- **Target:** macOS 26+, App Sandbox OFF, ad-hoc signed
- **Global Hotkeys:** soffes/HotKey (Carbon)
- **Capture / OCR / effects:** ScreenCaptureKit (`SCScreenshotManager`), Vision (`RecognizeTextRequest`, `DetectBarcodesRequest`), Core Image
- **Paste Mechanism:** CGEvent simulation (requires Accessibility permissions)

## Build & Run

```bash
swift build                    # debug build
swift build -c release         # release build
swift test                     # all tests (OCR tests run real Vision; the first run after a rebuild is slow)
swift test --skip "OCRServiceTests|OCRIndexerTests|TextCapturePipelineTests"   # fast subset

./scripts/build-app.sh debug   # Bufr-Debug.app: bundle id com.bufr.app.debug, data in ~/Library/Application Support/Bufr-Debug
open Bufr-Debug.app
```

- Test capture features with the `.app`, not `.build/debug/Bufr`: macOS attributes Screen Recording permission to the process that launches a bare binary (e.g. Terminal).
- Debug builds never touch the installed app's data (separate folder and bundle id) — `eraseDatabaseOnSchemaChange` is on in DEBUG.

## Architecture

The app follows a layered architecture with clear separation between clipboard monitoring, data persistence, and UI:

```
App/          → Entry point (BufrApp.swift), AppState (composition root), AppActivation, launch notices
Core/         → Clipboard polling, ClipIngestor (single write path into history), PasteboardWriter,
                paste simulation, HotKeyManager (multi-action, macOS-shortcut aware), permissions
Models/       → ClipItem, ClipOrigin, Pinboard, ContentType, HotKeyAction/Binding
Storage/      → GRDB migrations, stores, ImageStorage (images, thumbnails, editor sidecars), AppPaths
Capture/      → ScreenCaptureKit wrapper, capture session, overlay (freeze frame, selection, loupe), geometry
Screenshots/  → ScreenshotCoordinator (capture → PNG → history → folder → clipboard), settings, file naming
QuickAccess/  → Thumbnail stack after a capture
ScreenPin/    → Screenshots pinned above all windows
OCR/          → Vision text/QR recognition, background OCRIndexer (actor)
Editor/       → Annotation model, geometry, renderer, canvas, editor window, AnnotationStore
Views/        → SwiftUI views (PanelWindow, MenuBar, Pinboards, Settings, Onboarding, Common)
Utilities/    → Content type detection, color extraction, hashing, ImageEncoder
```

### Key Architectural Decisions

- **Floating panel** uses `NSPanel` with `.nonactivatingPanel` level so it doesn't steal focus from the active app
- **Clipboard monitoring** polls `NSPasteboard.changeCount` every 1.0 s on the main actor; writes Bufr makes itself carry the `com.bufr.app.self-write` pasteboard type and are skipped
- **History writes** go through `ClipIngestor` (hash → dedup → PNG normalization → file named after the item id)
- **Screenshots** are `ContentType.image` items with `origin = .screenshot`, inserted without dedup; the PNG is also saved to `~/Pictures/Bufr` (`saved_file_path`)
- **Coordinates:** capture code converts between Cocoa global (bottom-left), CG global (top-left) and display-local rects in `Capture/ScreenGeometry.swift` — use it, never `NSScreen.main` for the primary height
- **OCR:** `OCRIndexer` fills `ocr_text` (NULL = pending, "" = no text) for every image; Vision calls are serialized (`OCRSerialQueue`) because concurrent requests fail
- **Editor files:** `<uuid>.png` is the flattened result, `<uuid>_orig.png` the untouched original, `<uuid>.annotations.json` the layers
- **Paste action** writes to NSPasteboard then simulates ⌘V via CGEvent — requires Accessibility permissions
- **Images** stored on disk with only paths in SQLite; thumbnails generated for card previews with lazy loading
- **Security:** respects `org.nspasteboard.ConcealedType` (password managers), skips transient pasteboard items
- **Deduplication** via content hashing before insert

### Data Model

SQLite tables: `clip_items` (with FTS5 virtual table over `text_content`, `source_app_name`, `custom_title`, `ocr_text`), `pinboards`, `pinboard_items` (junction), `excluded_apps`. Migrations live in `Storage/AppDatabase.swift`; v4 added `origin`, `ocr_text`, `annotation_path`, `saved_file_path`, `pixel_width`, `pixel_height` (all optional — `ClipItem`'s Codable is also the `.bufr` export format).

### Auto-Update System

Custom updater based on GitHub Releases API (no Sparkle). Located in `Core/AppUpdater.swift`.

- **Repository:** `KodyaTemirov/bufr` — checks `GET /repos/{owner}/{repo}/releases/latest`
- **Version parsing:** `Models/AppVersion.swift` — semantic versioning (parses `1.2.3` and `v1.2.3` tags)
- **Verification:** SHA-256 hash from GitHub release body (format: `SHA256: <hex>`), verified via CryptoKit
- **Install flow:** download ZIP → verify hash → extract with `/usr/bin/ditto` → backup current .app → replace → `xattr -cr` → relaunch via `/bin/sh`
- **Auto-check:** on launch if enabled, throttled to once per hour, 3s delay
- **Settings:** `autoCheckEnabled`, `lastUpdateCheckDate` persisted in UserDefaults
- **UI:** section in GeneralSettingsView, menu item in MenuBarView, modal UpdateAlertView sheet
- **Build script** (`scripts/build-app.sh`): release builds create the ZIP and print the SHA-256 hash for GitHub release notes; debug builds produce `Bufr-Debug.app` only

## Creating a Release

1. Update version in `SupportFiles/Info.plist` — change `CFBundleShortVersionString` (e.g. `1.1.0`) and `CFBundleVersion`
2. Build the app:
   ```bash
   ./scripts/build-app.sh release
   ```
3. The script outputs the SHA-256 hash at the end — copy it
4. Create a GitHub release on `KodyaTemirov/bufr`:
   - Tag: `v1.1.0` (must match the version from Info.plist, prefixed with `v`)
   - Attach `Bufr.app.zip` as a release asset
   - Include the hash in the release body on a separate line:
     ```
     SHA256: <hash from build script>
     ```
   - The updater parses this line to verify downloads. If omitted, verification is skipped
