# Contributing to Pinax

Thanks for helping. Pinax moves users' files, so safety comes first. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), especially the safety contract.

## Build and test

Requires macOS 26+, Apple Silicon, Xcode with a Swift 6 toolchain.

```sh
swift build                       # debug build
swift test                        # PinaxCore tests (use temp directories, never the real Trash)
./build.sh                        # release Pinax.app, arm64, ad-hoc signed
./build.sh dmg                    # also dist/ DMG, ZIP, SHA256SUMS.txt
PINAX_SMOKE=1 swift test          # optional: read-only scan of your real home
PINAX_REAL_TRASH_QA=1 swift test  # optional: real-Trash QA with files it creates itself
```

## Conventions

- `PinaxCore` has no UI imports and no localization. Describe a reason with `ReasonKind`; localize it in `Sources/Pinax/Texts.swift`.
- Every user-visible string in the app is bilingual: `L("English", "Tiếng Việt")` (see `Loc.swift`, `Texts.swift`). Add both languages.
- Any destructive path goes through `Trasher` and `Executor`, and through `PathGuard`. Never call `removeItem` on user files. This check must only show `Trasher.swift` and the empty-directory case in `Executor.swift`:
  ```sh
  grep -rn "removeItem\|trashItem" Sources
  ```
- Treat unknown data as unknown: a nil last-used date never means "old".
- Do not follow symlinks; skip iCloud placeholders.
- Match the surrounding code: naming, comment density, `RuleKit` helpers.
- Plans for new milestones go in `docs/plans/` before code.

## Pull request checklist

- [ ] `swift build` and `swift test` pass; new behavior has tests.
- [ ] `./build.sh` works and you launched the app and looked at the affected screens.
- [ ] The `grep` check above shows no new `removeItem`/`trashItem`.
- [ ] New strings have English and Vietnamese.
- [ ] `CHANGELOG.md` updated under `[Unreleased]`.
- [ ] README/GUIDE updated if user-visible behavior changed.
- [ ] No `dist/` or build products committed.

## Adding a clean rule

1. Create `Sources/PinaxCore/Rules/<Name>Rule.swift` with a struct conforming to `CleanRule` (`id`, `group` = `.safe` or `.review`, `title`, `scan(_:)`). Wrap the body in `RuleKit.run(id) { ... }`, call `Task.checkCancellation()` in loops.
2. Build candidates only with `RuleKit.makeCandidate` (it applies `PathGuard` and reads the fingerprint). Skip symlinks and iCloud placeholders. Never use nil last-used to flag something. Decide `preselected` conservatively; only regenerable or clearly used-up data may be pre-ticked.
3. Add a `ReasonKind` case if needed, and its localized text in `Texts.swift` (plus the rule's title and description by id).
4. Register the rule in `RuleEngine.standard()`. Order matters: the first rule claims a path.
5. If it needs a threshold, add it to `CleanSettings`, `SettingsView`, and the Settings texts.
6. Tests in `Tests/PinaxCoreTests/RulesTests.swift` using the fake-home helpers: finds what it should; ignores what it should (below threshold, symlinks, nil dates, protected paths); preselect behavior; dedupe against other rules; permission-error status if it can occur.
7. Update `standardEngineOrderAndEvents` test, GUIDE rule table, CHANGELOG.
