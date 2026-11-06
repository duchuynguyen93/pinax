# Changelog

All notable changes to Pinax are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/), versioning follows [SemVer](https://semver.org/).

## [Unreleased]

## [0.6.0] - 2026-11-06

Milestone M6: search in the browser.

### Added
- **Search** (Cmd+F, or the field in the toolbar). Two scopes: **This Folder** filters the current list as you type; **Subfolders** finds matching names at every level below the current folder, with a **Where** column showing each result's folder. Matching ignores case and accents ("tai lieu" finds "Tài liệu", "da lat" finds "Đà Lạt"); several words must all appear in the name.
- Subfolder search uses Spotlight on the startup disk (fast, results update when files change) and Pinax's own folder walk on other disks. Up to 5,000 results; hidden files only when Show Hidden Files is on; contents of apps and other packages are not searched.
- Results work like a normal list: open, Quick Look, copy, drag out, rename, Move to Trash, Copy Path. New Folder, Paste and Duplicate are off while searching subfolders (there is no single folder to put things in). Moving to another folder ends the search.

## [0.5.0] - 2026-11-06

Milestone M5: see what is taking up space.

### Added
- **Space Map** (sidebar > Pinax): scans your home folder (or any folder you choose) and lists what takes the most space, level by level. A bar shows the largest items; double-click or Return opens a folder, Cmd+Up or the breadcrumb goes back. Sizes are real space on disk: symlinks are not followed, other disks mounted inside are not counted, hard links count once, apps and other packages are one item, and files under 1 MB are grouped per folder. Folders found while the scan runs appear straight away.
- Move to Trash (Cmd+Delete) from Space Map goes through the same checks and History as everything else, Cmd+Z puts it back. Space previews, the right-click menu has Reveal in Browser and Analyze Here.
- **Analyze Size** in the browser's right-click menu opens Space Map on that folder.

### Safety
- Space Map only reads. `~/Library/Containers` and `~/Library/Group Containers` are not opened during a scan (macOS would ask "access data from other apps"); they show as "Not scanned" with a Scan button you press yourself. Folders that need Full Disk Access are listed as unreadable.

## [0.4.0] - 2026-11-05

Milestone M4: uninstall apps cleanly and find what deleted apps left behind.

### Added
- **Uninstall Apps** (sidebar > Pinax): pick an installed app (or drop a `.app` on the screen) to see the app and everything it keeps in `~/Library`: Application Support, Caches, Preferences (and ByHost), Saved Application State, HTTPStorages, WebKit, Logs, Cookies, LaunchAgents and its own Container. Items found by bundle id are ticked; items only matching the app's name or a shared developer group container are listed but not ticked. Running apps are asked to quit first. Everything goes to the Trash as one History entry, undone with Cmd+Z. System apps and Pinax are not listed.
- **App leftovers** rule in Smart Clean ("Your call", nothing pre-ticked): items in `~/Library` named after the bundle id of an app that is no longer installed and not touched for 30 days (Settings > Leftovers). It is deliberately cautious: it skips anything belonging to an app found in /Applications, ~/Applications, Spotlight or LaunchServices (including helpers and other apps from the same developer or with the same name), command-line tools found in Homebrew / `~/.local/bin` / cargo and similar folders, system components, folders with recently changed contents, and LaunchAgents whose program still exists. Containers are never scanned.
- Quick Look (Space) on a focused row in Smart Clean results and in the Uninstall list.

## [0.3.0] - 2026-11-05

Milestone M3: copy and move without Finder, two panes, workspaces.

### Added
- **Copy, move and duplicate** with a transfer queue: a strip above the status bar shows bytes copied, the current item and a Stop button; jobs run one at a time. APFS copies are instant clones. Every job is one History entry and Cmd+Z undoes it.
- Clipboard like Finder: Cmd+C copies files (paste them in Finder too), Cmd+V pastes (also files copied in Finder), Option+Cmd+V moves them here ("Move Item Here"), Cmd+D duplicates (`name copy.ext`).
- **Name conflicts** ask once per job: Keep Both (`name 2.ext`), Replace (the old item goes to the Trash, so it is undoable), Skip, or Cancel.
- **Drag and drop**: drag files out to Finder or other apps; drop files from anywhere onto the list, the icon grid, a folder row or a Favorite. Same disk moves, another disk copies; hold Option to copy, Command to move.
- **Dual Pane** (View > Dual Pane, Cmd+\\): two folders side by side, each with its own history and selection; Tab switches panes; F5 copies and F6 moves the selection to the other pane. The layout is restored with the window.
- **Workspaces**: File > Save Window as Workspace (Ctrl+Cmd+S) saves every tab of the window (with dual-pane folders and view mode); open one from the sidebar or with `pinax://workspace?name=...`. Rename, update or delete from the right-click menu; deleting a workspace never touches files. Opening a workspace does not change your default view mode.

### Safety
- A copy is written under a hidden temporary name and only renamed into place when complete; a cancelled or failed copy is moved to the Trash, never deleted.
- Moving to another disk copies first, then moves the original to the Trash. Undoing a copy moves the copy to the Trash.
- Folders cannot be copied or moved into themselves; Replace refuses when the old item contains the source.

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

[Unreleased]: https://github.com/duchuynguyen93/pinax/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/duchuynguyen93/pinax/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/duchuynguyen93/pinax/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/duchuynguyen93/pinax/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/duchuynguyen93/pinax/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/duchuynguyen93/pinax/releases/tag/v0.1.0
