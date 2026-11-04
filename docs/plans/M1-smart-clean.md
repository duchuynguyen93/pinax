# M1 — Smart Clean + Tidy Downloads

> Tên app: **Pinax** (πίναξ — theo Pinakes, danh mục của Thư viện Alexandria) (bundle id `com.duchuynguyen93.pinax`). Đổi tên sau chỉ cần sửa Package.swift, build.sh, Info.plist.
> Phạm vi M1: tiện ích dọn dẹp chạy dạng cửa sổ. KHÔNG có trình duyệt file, path bar, dual pane, Workspaces,
> "đặt làm trình duyệt mặc định" / `NSFileViewer` — tất cả để M2/M3.

## 0. Quyết định chốt

| Hạng mục | Quyết định | Lý do |
|---|---|---|
| Ngôn ngữ / UI | Swift 6.4 toolchain, SwiftUI, AppKit khi cần | |
| Swift language mode | **Swift 5 mode** (`swiftLanguageModes: [.v5]`) | Tránh sa lầy strict-concurrency trong code duyệt file. Vẫn dùng async/await + `@MainActor` cho UI. |
| Min macOS | **26.0** | Chỉ test được trên máy macOS 27; không phải rải `@available` không kiểm chứng được. |
| Cấu trúc | **SwiftPM** (khác UsageRail cố ý): `PinaxCore` (library, không UI) + `Pinax` (executable SwiftUI) + `PinaxCoreTests` | App này chuyển file vào Thùng rác → bắt buộc có test cho core. |
| Build | `build.sh` chạy `swift build -c release`, rồi đóng `.app` như UsageRail (Info.plist heredoc, copy binary, ad-hoc codesign, tuỳ chọn `dmg`) | Giữ quy ước repo cũ. |
| Localization | Copy pattern `Loc.swift` của UsageRail (`L("en", "vi")`, `LangPref` system/en/vi) | Các app của user đều song ngữ. |
| Ký | Ad-hoc. Không phụ thuộc Developer ID | Xem §7. |
| Sandbox | Không sandbox | Phát hành ngoài App Store, cần đọc tự do trong home. |

## 1. Hợp đồng an toàn (KHÔNG được vi phạm)

1. Mọi thao tác xoá đều là `FileManager.trashItem(at:resultingItemURL:)`. **Cấm** `removeItem` lên file của người dùng (chỉ được dùng cho file tạm của chính app).
2. Ngay trước khi thao tác, mỗi candidate được **xác thực lại**: còn tồn tại, `contentModificationDate` và `fileSize` trùng lúc quét. Sai → bỏ qua item đó, báo "đã thay đổi từ lúc quét".
3. **Deny-list cứng** (`PathGuard`), kiểm sau khi `resolvingSymlinksInPath()`:
   - Chỉ cho phép đường dẫn nằm trong `~` hoặc `/Applications`.
   - Cấm chính xác: `/`, `/System`, `/Library`, `/Applications` (thư mục gốc), `~`, `~/Library`, `~/Desktop`, `~/Documents`, `~/Downloads`, `~/Movies`, `~/Pictures`, `~/Music`, `~/.Trash`, `~/Library/Mobile Documents` (gốc).
   - Cấm mọi thứ bên trong `~/.Trash`, `~/Library/Mobile Documents/*` ở cấp gốc container.
   - Cấm app bundle id `com.apple.*` và chính Pinax.
4. Duyệt thư mục **không theo symlink** (kiểm `isSymbolicLinkKey`, bỏ qua). Không đi vào package (`.skipsPackageDescendants`) trừ khi đang tính size.
5. File iCloud chưa tải về (`ubiquitousItemDownloadingStatusKey != .current`) → bỏ qua.
6. Lỗi từng item (permission, root-owned, đang dùng) **không làm hỏng cả batch**: ghi kết quả từng item.
7. Mọi batch thành công đều ghi vào journal **trước khi** báo xong cho UI (§4).
8. Không có Empty Trash trong M1. Chỉ có nút "Mở Thùng rác" (`NSWorkspace.open(~/.Trash)`).
9. "Last used" = nil nghĩa là **không biết** → không bao giờ dùng nil để kết luận "lâu không dùng".

## 2. Cấu trúc repo

```
Pinax/
  Package.swift
  build.sh
  README.md            (EN, có mục cài đặt + Gatekeeper)
  LICENSE              (MIT)
  docs/plans/M1-smart-clean.md
  Sources/
    PinaxCore/
      Models/          Candidate.swift, RuleGroup.swift, ScanResult.swift, FileFingerprint.swift
      Context/         ScanContext.swift, LastUsedProvider.swift, Trasher.swift, Clock.swift
      Safety/          PathGuard.swift
      Scan/            SizeCalculator.swift, DirectoryWalker.swift, SpotlightQuery.swift, InstalledApps.swift
      Rules/           CleanRule.swift + 1 file/rule
      Tidy/            TidyPlanner.swift, FileKind.swift
      Journal/         Journal.swift, JournalStore.swift, Executor.swift
      Permissions/     FullDiskAccess.swift
    Pinax/
      main.swift / PinaxApp.swift
      Loc.swift
      Views/           SidebarView, SmartCleanView, RuleSectionView, StorageBarView, TidyView, HistoryView, SettingsView, ConfirmSheet
      ViewModels/      SmartCleanModel, TidyModel, HistoryModel
  Tests/PinaxCoreTests/
```

## 3. PinaxCore

### 3.1 Model

```swift
enum RuleGroup { case safe, review }          // "An toàn" / "Tuỳ bạn"
struct FileFingerprint: Codable, Hashable { let size: Int64; let modified: Date }
struct Candidate: Identifiable, Hashable {
  let id: UUID; let url: URL; let size: Int64   // allocated size
  let fingerprint: FileFingerprint
  let reason: String                             // đã localize, vd "Đã cài Slack.app"
  let lastUsed: Date?; var preselected: Bool
}
enum RuleStatus { case ok, needsFullDiskAccess, failed(String) }
struct RuleResult { let ruleID: String; let candidates: [Candidate]; let status: RuleStatus }
```

### 3.2 Context (để test được)

```swift
struct ScanContext {
  var home: URL                     // test: thư mục tạm giả làm home
  var applicationRoots: [URL]       // /Applications, ~/Applications
  var now: Date
  var lastUsed: LastUsedProvider    // thật: MDItem kMDItemLastUsedDate / kMDItemDateAdded; test: dict
  var installedApps: InstalledAppsProvider
  var settings: CleanSettings       // ngưỡng, xem 3.4
}
protocol Trasher { func trash(_ url: URL) throws -> URL }   // trả về URL trong Thùng rác
// thật: FileManager.trashItem; test: move sang thư mục tạm
```

`LastUsedProvider` thật dùng `MDItemCreateWithURL` + `MDItemCopyAttribute` (đồng bộ, không cần runloop), lấy `kMDItemLastUsedDate` và `kMDItemDateAdded`.

`InstalledAppsProvider`: liệt kê `.app` trong `applicationRoots` (độ sâu 2, cho thư mục con như `/Applications/Utilities`), đọc `CFBundleIdentifier`, `CFBundleName`, tên file.

### 3.3 Quét & size

- `SizeCalculator`: tổng `totalFileAllocatedSizeKey` (fallback `fileAllocatedSizeKey`) qua `FileManager.enumerator`, không theo symlink, có kiểm `Task.isCancelled`.
- `DirectoryWalker`: generator file với giới hạn độ sâu, bỏ qua file ẩn tuỳ chọn, bỏ qua package.
- `SpotlightQuery`: chạy `/usr/bin/mdfind -0 -onlyin <root> <query>` qua `Process`, timeout 20 s. Hết giờ / exit ≠ 0 / không có kết quả → caller dùng `DirectoryWalker`.
- Các rule chạy song song bằng `withTaskGroup`, UI nhận progress theo từng rule. Hỗ trợ Cancel.

### 3.4 Rules M1 (8 rule; "rác của app đã xoá" hoãn sang M1.5)

`protocol CleanRule { var id: String; var group: RuleGroup; var title: String; func scan(_ ctx: ScanContext) async -> RuleResult }`

| # | id | Nhóm | Phạm vi & cách nhận diện | Tick sẵn |
|---|---|---|---|---|
| 1 | `devCaches` | safe | Danh sách cứng, mỗi thư mục tồn tại = 1 candidate (size cả thư mục): `~/Library/Developer/Xcode/DerivedData`, `~/Library/Developer/CoreSimulator/Caches`, `~/Library/Caches/Homebrew`, `~/.npm/_cacache`, `~/Library/Caches/pip`, `~/Library/Caches/Yarn`, `~/Library/Caches/CocoaPods`, `~/Library/Caches/org.swift.swiftpm`, `~/.gradle/caches`. Bỏ qua nếu < 10 MB. | có |
| 2 | `devStale` | review | `~/Library/Developer/Xcode/iOS DeviceSupport/*`; `node_modules` trong `settings.projectRoots` (mặc định `~/Code`, `~/Developer`, `~/Projects` nếu tồn tại; độ sâu 6; không đi vào chính node_modules) mà thư mục cha có mtime cũ hơn 180 ngày. | không |
| 3 | `duplicates` | safe/review | Trong Downloads, Desktop, Documents; file ≥ 1 MB; bỏ package, iCloud chưa tải, cùng inode (hardlink). Pinax theo size → hash 64 KB đầu → SHA-256 toàn file (CryptoKit, stream 1 MB). Giữ bản có `lastUsed` mới nhất, nil thì `contentModificationDate` mới nhất. Các bản còn lại là candidate. Ghi chú UI: "APFS clone có thể khiến dung lượng thu hồi thực tế ít hơn". | chỉ khi **mọi** bản trong nhóm nằm trong Downloads |
| 4 | `installers` | safe | `.dmg`, `.pkg`, `.zip` cấp 1 trong Downloads và Desktop. Chuẩn hoá tên (lowercase, bỏ version `\d+(\.\d+)*`, bỏ token `universal|arm64|x64|intel|mac|macos|osx|setup|installer|latest`, bỏ ký tự không phải chữ/số) so với tên app đã cài đã chuẩn hoá (khớp nếu bằng nhau hoặc tên app ≥ 4 ký tự và là tiền tố). Bỏ DMG đang mount (`hdiutil info -plist` → `image-path`). Reason: "Đã cài <App>". | `.dmg`/`.pkg` có; `.zip` không |
| 5 | `mailDownloads` | safe | Con của `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads`. Lỗi permission → `needsFullDiskAccess`. | có |
| 6 | `largeFiles` | review | File ≥ `settings.largeFileMB` (mặc định 500) trong home, trừ `~/Library`, `~/.Trash`, Photos/Music library package. Spotlight `kMDItemFSSize > N`, fallback walker. Không trùng candidate của rule khác (dedupe theo path ở tầng model, ưu tiên rule safe). | không |
| 7 | `unusedApps` | review | `.app` trong applicationRoots, không `com.apple.*`, không Pinax, `lastUsed` **khác nil** và cũ hơn 180 ngày. Reason: "Mở lần cuối <ngày>". | không |
| 8 | `screenRecordings` | review | `.mov` trong Desktop, Documents, Movies và thư mục `defaults read com.apple.screencapture location` (nếu có), tên bắt đầu bằng `Screen Recording` hoặc `Bản ghi màn hình`, cũ hơn 30 ngày (theo max(lastUsed, created)). | không |
| 9 | `oldDownloads` | review | Item cấp 1 trong Downloads (file và thư mục), max(lastUsed, dateAdded) cũ hơn 90 ngày; nil cả hai → bỏ. Loại các item đã là candidate của rule 3/4. | không |

Dedupe giữa các rule: một path chỉ xuất hiện ở rule đầu tiên theo thứ tự bảng.

### 3.5 Tidy Downloads (`TidyPlanner`)

- Input: thư mục (mặc định `~/Downloads`). Chỉ **file lẻ cấp 1**.
- Bỏ qua: file ẩn, thư mục, alias/symlink, đuôi `.crdownload .download .part .partial .opdownload`, file sửa trong 60 s gần nhất, file nằm trong danh sách thư mục category đích.
- `FileKind` theo `UTType` conformance, thứ tự kiểm: Installers (`.dmg .pkg .mpkg`) → Archives (`public.archive`, zip, rar, 7z, tar.*) → Images → Videos → Audio → Documents (pdf, text, rtf, office, iWork, csv) → Code (`public.source-code`, json, yaml, sh) → Other.
- Thư mục đích cố định M1 (tên tiếng Anh, không localize để ổn định): `Images, Videos, Audio, Documents, Archives, Installers, Code, Other`.
- Trùng tên ở đích → `name 2.ext`, `name 3.ext`… (cũng tính cả các file khác trong cùng plan).
- Output `TidyPlan { moves: [(from, to)], createdDirs: [URL], skipped: [(URL, reason)], bytesByKind }`. Preview trước, người dùng bỏ tick được từng nhóm.

### 3.6 Journal / Undo

```swift
enum JournalOp: Codable { case trash(original: URL, trashed: URL)
                          case move(from: URL, to: URL)
                          case createDir(URL) }
struct Batch: Codable, Identifiable { id, date, title, ops: [JournalOp], undone: Bool }
```
- Lưu `~/Library/Application Support/Pinax/journal.json`, ghi atomic, giữ 50 batch gần nhất.
- `Executor.perform(candidates|plan, trasher)` → thực thi tuần tự, xác thực lại từng item (§1.2), trả `[ItemOutcome]` (`done / skipped(reason) / failed(error)`); batch chỉ chứa op đã thành công; ghi journal rồi mới return.
- `Executor.undo(batch)`: đi ngược thứ tự. `trash`/`move`: nếu nguồn không còn → `skipped: đã mất`; nếu chỗ cũ đã có file → `skipped: chỗ cũ đã có file`; tạo thư mục cha nếu thiếu. `createDir`: chỉ xoá nếu rỗng (dùng `removeItem` được vì thư mục rỗng do app tạo — ngoại lệ duy nhất, ghi rõ trong code). Đánh dấu `undone`.
- ⌘Z trong menu Edit = undo batch mới nhất chưa undo.

### 3.7 Full Disk Access

- `FullDiskAccess.isGranted`: thử mở đọc `~/Library/Containers/com.apple.stocks` hoặc `/Library/Application Support/com.apple.TCC/TCC.db`; đọc được → true.
- Nút mở `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`.

## 4. UI (SwiftUI, 1 cửa sổ `NavigationSplitView`)

Sidebar: **Smart Clean**, **Downloads**, **History**, **Settings**.

- **Smart Clean**
  - Trên cùng: `StorageBarView` — dung lượng ổ khởi động (`volumeTotalCapacityKey`, `volumeAvailableCapacityForImportantUsageKey`), các đoạn: Apps (tổng size applicationRoots, tính nền), Thùng rác (`~/.Trash`), "Có thể dọn" (tổng đang tick), Còn lại, Trống.
  - Nút **Quét** / **Huỷ**, progress theo từng rule.
  - Hai section "An toàn để dọn" và "Tuỳ bạn quyết". Mỗi rule là một hàng: checkbox ba trạng thái, tiêu đề, tổng size, số item, mở ra thấy danh sách item (checkbox, tên, size, reason, nút "Hiện trong Finder").
  - Rule `needsFullDiskAccess` → hàng cảnh báo + nút mở System Settings; không chặn rule khác.
  - Đáy: "Chuyển X vào Thùng rác (n mục)" → sheet xác nhận → thực thi → toast "Đã chuyển n mục · **Hoàn tác**", báo item bị bỏ qua/lỗi.
- **Downloads**: tóm tắt dung lượng theo loại; preview `TidyPlan` theo nhóm (bỏ tick từng nhóm), danh sách bị bỏ qua có lý do; nút **Sắp xếp** → toast có Hoàn tác. Phím ⌥⌘T.
- **History**: danh sách batch (ngày, tiêu đề, số op, đã hoàn tác chưa), nút Hoàn tác từng batch, hiển thị kết quả từng op.
- **Settings**: ngôn ngữ (System/English/Tiếng Việt), ngưỡng file lớn, số ngày cho old downloads/unused apps, project roots, trạng thái Full Disk Access, nút "Mở Thùng rác".

Giao diện tự thiết kế, không sao chép FileOS.

## 5. Test bắt buộc (`swift test`, dùng Swift Testing hoặc XCTest)

Fixture: tạo home giả trong `FileManager.temporaryDirectory`, `TempTrasher` move vào thư mục tạm, `FixedLastUsed` dict, `FakeInstalledApps`.

1. `PathGuard`: từ chối các path cấm, path ra ngoài qua symlink, `~` và `~/Library`.
2. `duplicates`: nhóm đúng, chọn đúng bản giữ (theo lastUsed, rồi mtime), bỏ file < 1 MB, bỏ hardlink, preselect chỉ khi mọi bản trong Downloads.
3. `installers`: `Slack-4.41.105-macOS.dmg` khớp `Slack.app`; `Visual Studio Code.zip` / `VSCode-darwin-universal.zip` (chấp nhận không khớp cái thứ hai, ghi lại); `random.dmg` không khớp.
4. `oldDownloads` / `unusedApps`: nil lastUsed không bị gắn cờ; ngưỡng ngày đúng.
5. `TidyPlanner`: phân loại, bỏ `.crdownload` + file mới sửa + file ẩn + thư mục, trùng tên ra `x 2.pdf`, `x 3.pdf`.
6. `Executor` + `Journal`: perform → file nằm trong trash giả, journal có batch; undo → file về chỗ cũ; undo khi chỗ cũ đã có file → skipped; fingerprint thay đổi trước perform → skipped; journal ghi/đọc lại được sau khởi tạo mới.
7. Dedupe giữa các rule.

## 6. Kiểm chứng (cổng hoàn thành)

1. `swift build` và `swift test` xanh, không warning mới đáng kể.
2. `./build.sh` → `Pinax.app` (bản release, ad-hoc sign).
3. Mở `Pinax.app` thật, quét trên máy thật, **chụp màn hình** từng màn (Smart Clean sau quét, Downloads preview, History) và tự nhìn.
4. Tidy: Settings cho chọn thư mục Tidy (mặc định Downloads). QA trên một thư mục tạm chứa file mẫu → Sắp xếp → Hoàn tác → so `ls -laR` trước/sau phải giống hệt.
5. Smart Clean: tạo 2 bản sao một file 2 MB trong `~/Downloads` (tên `pinax-qa-*`), quét, **chỉ tick file QA**, chuyển vào Thùng rác, kiểm tra trong `~/.Trash`, Hoàn tác, kiểm tra về chỗ cũ. Xoá file QA sau khi xong.

## 7. Phát hành & Gatekeeper (ghi vào README)

- Ad-hoc signing: chữ ký đổi mỗi lần build → quyền Full Disk Access và prompt Downloads/Desktop/Documents **bị reset sau mỗi lần build lại**. Bình thường khi dev.
- Người dùng tải bản ad-hoc từ GitHub sẽ bị Gatekeeper chặn: hướng dẫn System Settings → Privacy & Security → "Open Anyway", hoặc `xattr -dr com.apple.quarantine /Applications/Pinax.app`.
- Có Developer ID ($99/năm) thì thêm bước notarize vào `build.sh` sau — M1 không phụ thuộc.

## 8. Chia việc cho implementer

| Bước | Việc | Phụ thuộc | Song song? |
|---|---|---|---|
| A | Package.swift, build.sh, README/LICENSE khung, Models, Context, PathGuard, SizeCalculator, DirectoryWalker, Journal + Executor + test 1 & 6 | — | |
| B | Rules 1–9 (trừ leftovers) + InstalledApps, SpotlightQuery, LastUsedProvider thật + test 2,3,4,7 | A | song song với C |
| C | TidyPlanner + FileKind + test 5 | A | song song với B |
| D | App SwiftUI (Loc, views, view models, FDA) | A, B, C | |
| E | Opus review diff → sửa → `./build.sh`, chạy app, chụp màn hình, QA §6 | D | |

## 9. Để sau (M1.5 / M2)

- M1.5: rule "rác của app đã xoá" (`~/Library/Application Support|Caches|Preferences|Containers|Saved Application State` với tên reverse-DNS không khớp app đã cài, cũ hơn 30 ngày, nhóm review), Empty Trash (cần Finder automation), Quick Look trong danh sách.
- M2: trình duyệt file, path bar + git, mở Terminal/Editor, đặt làm trình duyệt mặc định (`public.folder` handler + `NSFileViewer`), phím tắt toàn cục.
