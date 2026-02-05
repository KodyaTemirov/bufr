# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Clipo is a free, open-source, native macOS clipboard manager built with Swift and SwiftUI. It aims to replicate the visual clipboard history experience of Paste (pasteapp.io) — horizontal card ribbon, pinboards, fuzzy search — while being completely free and privacy-focused (all data stored locally).

The project specification is in `doc.md` (written in Russian). No source code has been implemented yet.

## Tech Stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI + AppKit (for system-level integrations like NSPanel, NSPasteboard)
- **Storage:** SQLite via GRDB.swift (with FTS5 for full-text search)
- **Package Manager:** Swift Package Manager
- **Target:** macOS 14.0 (Sonoma)+, App Sandbox OFF
- **Global Hotkeys:** Carbon HotKey API / MASShortcut
- **Paste Mechanism:** CGEvent simulation (requires Accessibility permissions)

## Build & Run

Once the Xcode project is created:

```bash
# Build from command line
xcodebuild -scheme Clipo -configuration Debug build

# Run tests
xcodebuild -scheme Clipo -configuration Debug test

# Build for release
xcodebuild -scheme Clipo -configuration Release build
```

Or open `Clipo.xcodeproj` / `Clipo.xcworkspace` in Xcode and use ⌘B / ⌘R.

## Architecture

The app follows a layered architecture with clear separation between clipboard monitoring, data persistence, and UI:

```
App/          → Entry point (ClipoApp.swift), global state (@Observable), menu bar
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

## Development Phases

The spec outlines 6 phases. When implementing, follow this order:
1. **Foundation** — Xcode project, models, GRDB setup, clipboard monitor, menu bar, exclusions
2. **UI Panel** — NSPanel floating window, horizontal card scroll, hotkey, keyboard nav, animations
3. **Search & Paste** — FTS5 search bar, filters, CGEvent paste, multi-paste, drag & drop
4. **Settings & Polish** — Settings window, hotkey customization, auto-launch (SMAppService), themes
5. **Pinboards** — Board CRUD, tab UI, add-to-board context menu
6. **Final Polish** — Quick Look, inline editing, onboarding, tests, notarization, DMG
