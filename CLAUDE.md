# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Bufr is a free, open-source, native macOS clipboard manager built with Swift and SwiftUI. It aims to replicate the visual clipboard history experience of Paste (pasteapp.io) — horizontal card ribbon, pinboards, fuzzy search — while being completely free and privacy-focused (all data stored locally).

The project specification is in `doc.md` (written in Russian).

## Tech Stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI + AppKit (for system-level integrations like NSPanel, NSPasteboard)
- **Storage:** SQLite via GRDB.swift (with FTS5 for full-text search)
- **Package Manager:** Swift Package Manager
- **Target:** macOS 14.0 (Sonoma)+, App Sandbox OFF
- **Global Hotkeys:** Carbon HotKey API / MASShortcut
- **Paste Mechanism:** CGEvent simulation (requires Accessibility permissions)

## Build & Run

```bash
# Build from command line
swift build

# Build for release
swift build -c release

# Run debug binary
.build/debug/Bufr
```

## Architecture

The app follows a layered architecture with clear separation between clipboard monitoring, data persistence, and UI:

```
App/          → Entry point (BufrApp.swift), global state (@Observable), menu bar
Core/         → Clipboard polling (NSPasteboard), paste simulation (CGEvent),
                hotkey registration, app exclusion rules
Models/       → ClipItem, Pinboard, ContentType enum
Storage/      → GRDB database setup/migrations, CRUD stores, image disk storage
Views/        → SwiftUI views organized by feature (PanelWindow, MenuBar, Pinboards, Settings)
Utilities/    → Content type detection, syntax highlighting, color extraction, URL metadata
```

### Key Architectural Decisions

- **Floating panel** uses `NSPanel` with `.nonactivatingPanel` level so it doesn't steal focus from the active app
- **Clipboard monitoring** polls `NSPasteboard.changeCount` every 500ms on a background thread
- **Paste action** writes to NSPasteboard then simulates ⌘V via CGEvent — requires Accessibility permissions
- **Images** stored on disk with only paths in SQLite; thumbnails generated for card previews with lazy loading
- **Security:** respects `org.nspasteboard.ConcealedType` (password managers), skips transient pasteboard items
- **Deduplication** via content hashing before insert

### Data Model

SQLite tables: `clip_items` (with FTS5 virtual table for search), `pinboards`, `pinboard_items` (junction), `excluded_apps`. Schema defined in `doc.md` section 4.

### Auto-Update System

Custom updater based on GitHub Releases API (no Sparkle). Located in `Core/AppUpdater.swift`.

- **Repository:** `KodyaTemirov/bufr` — checks `GET /repos/{owner}/{repo}/releases/latest`
- **Version parsing:** `Models/AppVersion.swift` — semantic versioning (parses `1.2.3` and `v1.2.3` tags)
- **Verification:** SHA-256 hash from GitHub release body (format: `SHA256: <hex>`), verified via CryptoKit
- **Install flow:** download ZIP → verify hash → extract with `/usr/bin/ditto` → backup current .app → replace → `xattr -cr` → relaunch via `/bin/sh`
- **Auto-check:** on launch if enabled, throttled to once per hour, 3s delay
- **Settings:** `autoCheckEnabled`, `lastUpdateCheckDate` persisted in UserDefaults
- **UI:** section in GeneralSettingsView, menu item in MenuBarView, modal UpdateAlertView sheet
- **Build script** (`scripts/build-app.sh`): creates ZIP and outputs SHA-256 hash for GitHub release notes

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
