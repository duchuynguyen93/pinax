# Architecture

Pinax is a SwiftPM package with three targets.

```
Package.swift            swift-tools 6.0, Swift 5 language mode, macOS 26
Sources/PinaxCore/       library, no UI imports, fully testable
  Models/                Candidate, ReasonKind, RuleGroup, FileFingerprint
  Context/               ScanContext, CleanSettings, providers, Trasher
  Safety/                PathGuard (deny-list)
  Scan/                  SizeCalculator, DirectoryWalker, SpotlightQuery, FileHasher,
                         ProcessRunner, MountedImages, installed-apps and last-used providers
  Rules/                 CleanRule, RuleEngine, RuleSupport, one file per rule
  Selection/             Selection (effective selection, duplicate-keeper conflicts)
  Tidy/                  TidyPlanner, FileKind
  Journal/               Journal (Batch, JournalOp, outcomes), JournalStore, Executor
  Permissions/           FullDiskAccess
Sources/Pinax/           SwiftUI executable
  PinaxApp.swift         scene, menu commands (Cmd+Z, Option+Cmd+T)
  Loc.swift, Texts.swift L("en","vi") helper and localized strings for core enums
  ViewModels/            AppEnvironment, SmartCleanModel, TidyModel, HistoryModel, AppSettings, ToastModel
  Views/                 Sidebar, SmartClean, RuleSection, StorageBar, Tidy, History, Settings, ConfirmSheet, Toast
Tests/PinaxCoreTests/    Swift Testing suites for the core
```

PinaxCore has no localization and no UI: candidates carry a structured `ReasonKind`, and the app layer turns it into text.

## Data flow: Smart Clean

```
ScanContext (home, app roots, now, settings, providers)
   -> RuleEngine.run: every CleanRule.scan in parallel (withTaskGroup)
   -> RuleEngine.dedupe: a path stays only in the first rule (table order)
   -> [RuleResult] -> Candidates (url, size, fingerprint, reason, preselected)
   -> SmartCleanModel: user ticks -> Selection.effectiveSelection (drop children of selected parents)
      + duplicateKeeperConflicts (block selecting every copy)
   -> Executor.perform(candidates:trasher:) re-validates each item, trashes via Trasher
   -> Batch of .trash ops -> JournalStore.append (before returning to the UI)
   -> toast / History -> Executor.undo(batch)
```

Rules never mutate anything; they only produce candidates. Rule order: devCaches, devStale, duplicates, installers, mailDownloads, largeFiles, unusedApps, screenRecordings, oldDownloads. A rule failure or cancellation becomes a `RuleStatus` and never aborts the others; a missing permission becomes `needsFullDiskAccess`.

## Data flow: Tidy

```
TidyPlanner.plan(folder, now, home) -> TidyPlan (moves, createDirs, skipped, bytesByKind)
   -> TidyPlan.filtered(kinds:) (per-type opt-out in the UI)
   -> Executor.perform(moves:createDirs:title:home:) (createDir + move ops, never overwrites)
   -> Batch -> JournalStore.append -> undo reverses ops (createDir only if empty)
```

## Safety contract

Carried over from [plans/M1-smart-clean.md](plans/M1-smart-clean.md) section 1; numbering is kept.

1. Every deletion is `FileManager.trashItem(at:resultingItemURL:)`. `removeItem` on user files is forbidden (it may only be used on app temp files and the empty-directory exception in Undo).
2. Right before acting, each candidate is re-validated: it still exists and its `contentModificationDate` and `fileSize` equal the scan values. If not, that item is skipped and reported as "changed since scan".
3. A hard deny-list (`PathGuard`), checked after `resolvingSymlinksInPath()`:
   - only paths inside `~` or `/Applications` are allowed;
   - these exact paths are denied: `/`, `/System`, `/Library`, `/Applications` (the root), `~`, `~/Library`, `~/Desktop`, `~/Documents`, `~/Downloads`, `~/Movies`, `~/Pictures`, `~/Music`, `~/.Trash`, `~/Library/Mobile Documents` (the root);
   - everything inside `~/.Trash` and the root of each iCloud container under `~/Library/Mobile Documents/` is denied;
   - app bundles with id `com.apple.*` and Pinax itself are never touched.
4. Directory traversal does not follow symlinks (they are skipped). Packages are not descended into, except to measure size.
5. iCloud files not downloaded locally (`ubiquitousItemDownloadingStatus != .current`) are skipped.
6. A failure on one item (permission, root-owned, in use) never fails the batch; each item gets its own outcome.
7. Every successful batch is written to the journal before the UI is told it is done.
8. No Empty Trash. The app only offers "Open Trash".
9. "Last used" being nil means unknown. Nil is never used to conclude "unused for a long time".

Copy and move (M3, [plan](plans/M3-dual-pane-transfers.md) section 3): copies are written under a hidden `.pinax-partial-*` name and renamed into place with `RENAME_EXCL`, so a destination is never overwritten; a cancelled or failed partial copy goes to the Trash. A cross-disk move is copy then Trash of the original. Undoing a copy (`JournalOp.copy`) moves the copy to the Trash. Replace moves the old item to the Trash first. None of this adds a `removeItem`.

Batch rename (M7): every rename is an `Executor` move that never overwrites; swaps and chains go through hidden `.pinax-rename-*` names in the same folder, all journaled, so undo walks them back.

Tags (M8) are written with `NSURL.setResourceValue(_:forKey: .tagNamesKey)` directly, not through `Executor` or the journal: a tag changes neither content nor location, and toggling it again is the undo. They are only written on items `FileOps.canModify` allows. Cut (Cmd+X) is a Copy plus an in-memory marker; Cmd+V turns into a normal journaled move.

Path bar commands (M9, `PathCommand`) never run a shell: a command only maps to bundle ids and the folder is opened with `NSWorkspace.open(_:withApplicationAt:)`. Grouping (M9, `FileGrouping`) only reorders `BrowserModel.items`; the list and icon views map table rows / index paths back to that flat array.

Implementation notes: comparisons in `PathGuard` are case-insensitive (APFS default); `Executor` additionally refuses symlinks and protected app bundles regardless of where a candidate came from; Tidy never overwrites a destination. The single permitted `removeItem` is in `Executor.removeIfEmpty`, for empty directories Pinax itself created during Tidy.

## Testing strategy

- Rules and the executor run against a fake home in a temp directory (`Support.swift`, `RulesSupport.swift`), with fixed providers (`FixedLastUsed`, fake installed apps, stub Spotlight) and a temp-directory `Trasher`, so no test touches the real Trash.
- Suites: `PathGuardTests`, `RulesTests`, `ExecutorTests` (including journal reload and 50-batch cap), `TidyPlannerTests`, `SelectionTests`.
- `PINAX_SMOKE=1 swift test`: opt-in, runs the full `RuleEngine` against the real home, read-only.
- `PINAX_REAL_TRASH_QA=1 swift test`: opt-in, creates two `pinax-qa-*` files in `~/Downloads`, runs the duplicates rule, trashes one with the real Trasher, undoes it, and cleans up. It only touches the files it created.
- Visual check: build with `./build.sh`, launch `Pinax.app`, and look at each screen; test results alone do not catch layout problems.

## Key decisions

| Decision | Choice | Why |
|---|---|---|
| Structure | SwiftPM: `PinaxCore` + `Pinax` + tests | The app moves user files; the core must be testable without UI |
| Swift language mode | Swift 5 (`swiftLanguageModes: [.v5]`) | Avoids strict-concurrency friction in file-walking code; async/await and `@MainActor` still used |
| Minimum macOS | 26.0 | Only testable on current macOS; avoids unverified `@available` branches |
| Architecture | arm64 only | Built and tested on Apple Silicon |
| Sandbox | Off | Distributed outside the App Store; needs to read freely in the home folder |
| Signing | Ad-hoc | No paid Developer ID; users clear Gatekeeper manually (see README) |
| Delete mechanism | Trash only, plus journal | Everything reversible |
| Empty Trash | Not implemented | Irreversible; needs its own design (M1.5) |
| Localization | `L("en","vi")` helper, language preference | App is bilingual EN/VI |
| Version source | `VERSION` file | build.sh reads it for the bundle version |
