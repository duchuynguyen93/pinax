# Changelog

All notable changes to Pinax are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/), versioning follows [SemVer](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/duchuynguyen93/pinax/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/duchuynguyen93/pinax/releases/tag/v0.1.0
