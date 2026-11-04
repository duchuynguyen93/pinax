# AGENTS.md

Pinax: free, open-source macOS (26+, Apple Silicon) SwiftUI app that finds disk clutter and tidies Downloads. Everything it removes goes to the Trash and is undoable. Version in `VERSION`. Bundle id `com.duchuynguyen93.pinax`.

## Commands

```sh
swift build                       # debug build
swift test                        # core tests
./build.sh                        # release Pinax.app (arm64, ad-hoc signed)
./build.sh dmg                    # dist/Pinax-<version>-arm64.dmg, .zip, SHA256SUMS.txt
PINAX_SMOKE=1 swift test          # opt-in: read-only scan of the real home
PINAX_REAL_TRASH_QA=1 swift test  # opt-in: real Trash, only files it creates (pinax-qa-*)
```

## Repo map

- `Sources/PinaxCore/` logic, no UI: Models, Context, Safety (PathGuard), Scan, Rules, Selection, Tidy, Journal (Executor), Permissions.
- `Sources/Pinax/` SwiftUI: ViewModels, Views, `Loc.swift`/`Texts.swift` for bilingual strings.
- `Tests/PinaxCoreTests/` Swift Testing suites.
- `docs/ARCHITECTURE.md` design; `docs/plans/` one plan per milestone.
- `build.sh`, `VERSION`, `CHANGELOG.md`, `GUIDE.md`, `CONTRIBUTING.md`.

## Hard safety rules

Full contract: `docs/ARCHITECTURE.md#safety-contract`. Never break:

1. Delete only via `Trasher` (`FileManager.trashItem`) called from `Executor`. Never `removeItem` on user files.
2. Re-validate each item (exists, size and mtime equal to scan) right before acting.
3. Every path passes `PathGuard`; never touch `~`, `~/Library`, standard home folders, Trash, iCloud containers, `com.apple.*` apps, Pinax.
4. Do not follow symlinks; skip iCloud placeholders.
5. One item failing must not fail the batch; journal before reporting success.
6. nil last-used means unknown, never "old".
7. After any change, this must show only `Trasher.swift` and the empty-directory exception in `Executor.swift`:
   `grep -rn "removeItem\|trashItem" Sources`

## Conventions

- Core has no UI imports and no localization; UI text is `L("en","vi")` with both languages.
- Swift 5 language mode, macOS 26 only; no `@available` shims.
- Match surrounding code style and comment density. Do not add dependencies.
- Plans live in `docs/plans/`, one file per milestone. Write the plan before coding.

## Definition of done

- `swift build` and `swift test` green.
- `./build.sh` works; launch `Pinax.app` and visually check the affected screens (tests do not catch layout bugs).
- `CHANGELOG.md` updated; docs updated if behavior changed.

## Do not

- Add Empty Trash or any irreversible action without an explicit design in `docs/plans/`.
- Try to register Pinax as the default folder viewer (`public.folder` default handler, `NSFileViewer`): macOS 27 refuses it, see `docs/plans/M2-file-browser.md` §0.
- Commit `dist/`, `.build/` or `Pinax.app`.
- Change safety behavior without updating tests and the contract.
