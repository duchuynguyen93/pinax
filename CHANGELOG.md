# Changelog

All notable changes to Pinax are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/), versioning follows [SemVer](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-11-05

Milestone M2: Pinax becomes a file browser.

### Added
- **File browser** window (the main window): sidebar with Favorites, Locations (with Eject) and the Pinax tools; list view with sortable Name / Date Modified / Size / Kind columns and icon view with thumbnails and three sizes (Cmd+1 / Cmd+2, Cmd+- / Cmd+=); folder sizes computed in the background; breadcrumb path bar; Back / Forward / Enclosing Folder (Cmd+[ / Cmd+] / Cmd+Up); Go to Path (Cmd+L) with Tab completion (press again to cycle); Quick Look (Space); live refresh when the folder changes; tabs (Cmd+T); show hidden files (Shift+Cmd+.); status bar with item count and free space.
- File operations in the browser, all journaled, listed in History and undoable with Cmd+Z: New Folder (Shift+Cmd+N, then rename in place), Rename (Return; the name without extension is pre-selected, Esc cancels, case-only renames work, existing names are never overwritten), Move to Trash (Cmd+Delete, no confirmation, toast with Undo). Locations Pinax protects show "Pinax doesn't modify this location".
- Context menu in list and icon views (and on empty space): Open, Open With (default app first), Quick Look, Rename, New Folder, Move to Trash, Copy Path (Option+Cmd+C), Show in Finder, Open in Terminal / Editor.
- Git in the path bar: branch (or short SHA when detached), ahead/behind and change count with a tooltip breakdown. Read-only, runs in the background, only when Command Line Tools are installed.
- Ways into Pinax (it cannot be the default folder viewer on macOS 27, see `docs/plans/M2-file-browser.md` section 0): global shortcut (default Option+Cmd+P, recordable in Settings, no Accessibility permission), Services "Open in Pinax", Finder Open With for folders, `open -a Pinax <folder>`, and `pinax://open?path=...` URLs. A file opens its parent folder with the file selected; a missing path opens Home with a notice.
- Settings: choose the Terminal and Editor app (only installed ones are listed); File menu "Open in Terminal" (Option+Shift+Cmd+T) and "Open in Editor" (Option+Shift+Cmd+E).

### Changed
- The second "Downloads" entry in the sidebar is now "Tidy Downloads".
- Cmd+Z / Shift+Cmd+Z / Cmd+Delete act on the text while you are renaming or typing a path, instead of undoing a file batch or trashing the selection.

### Performance
- A 10,000-item folder opens in about 230 ms from launch and 225-285 ms in a new window (was 450-550 ms): listing starts without waiting for the window to finish building, sorting works on precomputed keys, and file types are cached per extension. `PINAX_PERF_LOG=1` prints the timings, release builds included.

### Fixed
- Opening a file, URL or `PINAX_OPEN` no longer produces an extra default window, and `PINAX_OPEN` no longer turns every restored window into an identical tab. `PINAX_OPEN` now applies to the first window only.

## [0.1.1] - 2026-11-04

### Added
- App icon: a clay writing tablet (the *pinax* of the Library of Alexandria's catalog) with a sparkle, drawn from vectors by `scripts/make-icon.swift` (`scripts/make-icon.sh` rebuilds `assets/AppIcon.icns`).
- Icon shown at the top of the README.

## [0.1.0] - 2026-11-04

First public release (milestone M1). Apple Silicon, macOS 26+, ad-hoc signed.

### Added
- **Smart Clean** with nine rules, grouped into "Safe to clear" and "Your call", scanned in parallel with per-rule progress and Cancel:
  - Developer caches (Xcode DerivedData, CoreSimulator caches, Homebrew, npm, pip, Yarn, CocoaPods, SwiftPM, Gradle), pre-ticked, 10 MB minimum.
  - Stale developer files: Xcode iOS DeviceSupport and old `node_modules` (180 days).
  - Duplicate files in Downloads, Desktop and Documents (size, 64 KB prefix, then SHA-256); keeps the most recently used copy; pre-ticked only when all copies are in Downloads.
  - Used installers (`.dmg`, `.pkg`, `.zip`) of apps that are already installed; mounted DMGs skipped.
  - Mail attachment cache (needs Full Disk Access).
  - Large files (500 MB by default) via Spotlight with a directory-walk fallback.
  - Apps not opened for 180 days (unknown last-used date is never flagged; Apple apps and Pinax excluded).
  - Screen recordings older than 30 days.
  - Old downloads (90 days).
- Cross-rule de-duplication: a path appears under one rule only; selecting a folder covers its children; guard against selecting every copy of a duplicate.
- **Tidy Downloads**: preview and sort loose files into Images, Videos, Audio, Documents, Archives, Installers, Code and Other; skips hidden files, folders, aliases, unfinished downloads and files modified in the last minute; conflicts become `name 2.ext`; per-type opt-out; configurable folder; Option+Cmd+T.
- **History and Undo**: JSON journal (`~/Library/Application Support/Pinax/journal.json`, last 50 batches, atomic writes), per-item outcomes, Cmd+Z, undo toast; empty folders created by Tidy are removed on undo.
- **Storage bar** showing Apps, Trash, Selected, Other and Free on the startup disk.
- **Settings**: language (System, English, Tiếng Việt), thresholds, project folders, Tidy folder, Full Disk Access status, Open Trash.
- Safety layer: Trash-only moves, re-validation against the scan fingerprint, `PathGuard` deny-list, no symlink following, iCloud placeholders skipped, per-item error isolation.
- Bilingual EN/VI interface.
- `build.sh` producing an arm64 `Pinax.app`, plus `./build.sh dmg` for `Pinax-<version>-arm64.dmg`, `.zip` and `SHA256SUMS.txt`.
- Documentation: README, user guide, architecture, contributing guide, AGENTS.md.

[Unreleased]: https://github.com/duchuynguyen93/pinax/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/duchuynguyen93/pinax/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/duchuynguyen93/pinax/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/duchuynguyen93/pinax/releases/tag/v0.1.0
