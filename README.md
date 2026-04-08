# Clipwise

A lightweight, native macOS clipboard manager — inspired by [Maccy](https://maccy.app/).

## Features

- **Clipboard History** — Automatically saves everything you copy (text, images, files)
- **Quick Search** — Fuzzy, exact, and regex search modes
- **Global Shortcuts** — `Cmd+Shift+C` (menu bar) / `Cmd+Shift+V` (at cursor)
- **Auto Paste** — Select an item and press Enter to paste directly into the active app
- **Preview** — Hover or select an item to see a full preview popover
- **Password Detection** — Automatically hides sensitive content (passwords, API keys, tokens)
- **Pin Items** — Keep important items at the top of your history
- **Ignored Apps** — Skip clipboard captures from password managers (1Password, Bitwarden, etc.)
- **Configurable History** — Set max items (default: 30)
- **Dark/Light Mode** — Follows system appearance

## Requirements

- macOS 14.0 (Sonoma) or later
- Accessibility permission (for auto-paste)

## Installation

1. Download `Clipwise-1.0.0.dmg` from [Releases](./release/)
2. Open the DMG and drag **Clipwise** to **Applications**
3. Launch Clipwise — it appears as a clipboard icon in the menu bar
4. Grant **Accessibility** permission when prompted (System Settings → Privacy & Security → Accessibility)

> First launch: macOS may show "unidentified developer" warning. Right-click the app → Open → "Open Anyway".

## Usage

| Shortcut | Action |
|---|---|
| `Cmd+Shift+C` | Toggle clipboard panel (near menu bar) |
| `Cmd+Shift+V` | Show clipboard panel (at cursor position) |
| `↑` / `↓` | Navigate items |
| `Enter` | Paste selected item |
| `Escape` | Close panel |
| Type anything | Search clipboard history |

## Build from Source

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -configuration Release build
```

## Tech Stack

- **Swift + SwiftUI** — UI rendering
- **AppKit** — `NSPanel` (floating window), `NSStatusItem` (menu bar)
- **SwiftData** — Clipboard history persistence (SQLite)
- **Carbon HIToolbox** — Global hotkey registration
- No third-party dependencies

## License

MIT
