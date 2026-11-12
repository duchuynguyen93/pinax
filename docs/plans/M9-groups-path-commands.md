# M9 — Nhóm theo Loại / Ngày, lệnh trên path bar (v0.9.0)

> Bù thêm hai chỗ thua FileOS: "Use Groups" như Finder và gõ lệnh kiểu `code .` ở ô đường dẫn.
> Không đụng Executor / PathGuard / Transfer core. Lệnh path bar KHÔNG chạy shell: chỉ mở thư mục bằng app (NSWorkspace).

## 1. Nhóm (Group By)

### Core — `Sources/PinaxCore/Browse/FileGrouping.swift` (thuần, có test)
```swift
public enum GroupBy: String, CaseIterable, Sendable { case none, kind, modified }
public enum KindGroup: Int, CaseIterable, Sendable, Comparable {
    case folder, application, document, pdf, spreadsheet, presentation, image, movie, music,
         archive, diskImage, sourceCode, other
}
public enum DateGroup: Hashable, Sendable { case today, yesterday, previous7Days, previous30Days,
    month(year: Int, month: Int), year(Int), unknown }
public enum GroupKey: Hashable, Sendable { case kind(KindGroup), date(DateGroup) }
public struct FileGroup: Equatable, Sendable { public let key: GroupKey; public let items: [FileItem] }
public enum FileGrouping {
    public static func kindGroup(_ item: FileItem) -> KindGroup
    public static func dateGroup(_ date: Date?, now: Date, calendar: Calendar) -> DateGroup
    public static func group(_ items: [FileItem], by: GroupBy, now: Date = Date(), calendar: Calendar = .current) -> [FileGroup]
}
```
- `kindGroup`: `isNavigableFolder` → folder. Còn lại theo `contentType` (nil → other), thứ tự kiểm: application/applicationBundle → application; pdf → pdf; diskImage → diskImage; archive → archive; sourceCode | script | shellScript | json | xml | yaml (UTType "public.yaml" nếu có) → sourceCode; spreadsheet → spreadsheet; presentation → presentation; image → image; movie | video | audiovisualContent-không-phải-audio → movie; audio → music; text | compositeContent → document; còn lại → other. Package không phải app → other. Cache kết quả theo `contentType.identifier` (+ cờ folder) bằng lock như `FileItem.TypeCache`.
- `dateGroup`: nil → unknown. `start = calendar.startOfDay(for: now)`. d ≥ start (kể cả tương lai) → today; ≥ start−1 ngày → yesterday; ≥ start−7 ngày → previous7Days; ≥ start−30 ngày → previous30Days; cùng năm với now → month(year, month); còn lại → year(y). Dùng `calendar.date(byAdding:)`, không cộng giây.
- `group`: `.none` → `[]` (UI coi là không nhóm). Giữ nguyên thứ tự đầu vào trong mỗi nhóm (đầu vào đã sắp theo `FileSort`). Thứ tự nhóm: kind theo thứ tự enum; date: today, yesterday, previous7Days, previous30Days, các tháng mới → cũ, các năm mới → cũ, unknown cuối. Bỏ nhóm rỗng. O(n).
- Test `Tests/PinaxCoreTests/FileGroupingTests.swift`: phân loại (folder, .app, pdf, png, mov, mp3, zip, dmg, swift, json, txt, docx, xlsx, key/pptx, không đuôi), ranh giới ngày (00:00 hôm nay, 23:59 hôm qua, đúng 7/8 ngày, 30/31 ngày, tháng trước cùng năm, năm trước, tương lai, nil) với `now` + `Calendar(identifier: .gregorian)` timezone cố định, thứ tự nhóm, giữ thứ tự trong nhóm, `.none` → rỗng.

### App
- `BrowserPrefs.groupBy: GroupBy` lưu `pinax.browser.groupBy` (mặc định `.none`); `didSet` post `BrowserPrefs.groupingChanged` (Notification.Name). Mọi `BrowserModel` nghe và gọi `rebuildItems()` (để mọi cửa sổ / pane cập nhật).
- `BrowserModel`:
  - `struct GroupSpan: Equatable { let title: String; let start: Int; let count: Int }` (start/count là chỉ số trong `items`).
  - `private(set) var groups: [GroupSpan] = []`.
  - Trong `rebuildItems()`, sau khi có danh sách đã lọc: nếu `prefs.groupBy != .none` → `FileGrouping.group(...)`, gán `items` = nối các nhóm theo thứ tự nhóm, `groups` = spans; không thì `groups = []`. `items` luôn là thứ tự hiển thị thật (bàn phím, Shift-chọn dải, Quick Look ←/→ dùng đúng thứ tự).
  - Tiêu đề (app, `L(en, vi)`): Folders/Thư mục, Applications/Ứng dụng, Documents/Tài liệu, PDF Documents/Tài liệu PDF, Spreadsheets/Bảng tính, Presentations/Bản trình chiếu, Images/Hình ảnh, Movies/Video, Music/Âm thanh, Archives/File nén, Disk Images/Ảnh đĩa, Source Code/Mã nguồn, Other/Khác; Today/Hôm nay, Yesterday/Hôm qua, Previous 7 Days/7 ngày trước, Previous 30 Days/30 ngày trước, tháng: `DateFormatter` "LLLL" theo locale hiện tại, viết hoa chữ đầu (`FileItem.capitalizingFirst`); năm: "2024"; unknown: Unknown Date/Không rõ ngày.
- Menu View (`PinaxApp.swift`, CommandGroup after .toolbar): submenu "Group By"/"Nhóm theo" với 3 Toggle/Picker: None ⌃⌘0, Kind ⌃⌘2, Date Modified ⌃⌘5. Tắt khi `browser == nil || browser?.pinax != nil`.
- Toolbar (`BrowserWindow.swift`, sau Picker kiểu xem): `Menu` icon `square.grid.3x1.below.line.grid.1x2` chọn nhóm (Picker inline), help "Group By". Ẩn / disabled khi `pinax != nil`.
- List view (`FileListView.swift`):
  - Coordinator giữ `rows: [Row]` với `enum Row { case header(GroupSpan), item(Int) }` (Int = chỉ số trong `items`), `rowByPath` → chỉ số dòng bảng. Khi `groups` rỗng: mỗi dòng là item, không có header (hành vi như cũ).
  - Mọi chỗ đang dùng `items[row]` đổi sang helper `item(atRow:) -> FileItem?` (nil với header / ngoài phạm vi): viewFor, rename, drag (pasteboardWriter trả nil cho header), validate/accept drop (header = như thả vào nền), selection (bỏ header), double-click, type-select (nil cho header), sizeResolved, refreshCutState.
  - `tableView(_:isGroupRow:)` true cho header; `floatsGroupRows = true`; `shouldSelectRow` false cho header; `selectionIndexesForProposedSelection` lọc header (⌘A không chọn header); `heightOfRow` header 24.
  - View header: chữ `.headline`-ish (systemFont 12 semibold) tiêu đề + số mục màu secondary ("Hình ảnh  12"), lề trái thẳng cột icon. Dùng `NSTableCellView` với identifier riêng, trả cho `tableColumn == nil` (group row trải hết bề rộng).
  - `BrowserTableView.menu(for:)`: chuột phải vào header → coi như chỗ trống (bỏ chọn).
- Icon view (`IconGridView.swift`):
  - Có nhóm → mỗi nhóm một section; không nhóm → 1 section như cũ. Coordinator giữ `sections: [GroupSpan]` (không nhóm → một span phủ hết, không header).
  - Helper `flatIndex(_ ip: IndexPath) -> Int` và `indexPath(forFlat:)`; thay mọi `items[indexPath.item]` / `items[i]` cho đúng. Vùng chọn, reveal, rename, drop, type-select, refreshCutState, sizeResolved theo helper.
  - Header: supplementary `NSCollectionView.elementKindSectionHeader`, class `GroupHeaderView: NSView, NSCollectionViewElement` (chữ như list), cao 28; `flowLayout.headerReferenceSize` = 0 khi không nhóm; `sectionHeadersPinToVisibleBounds = true`.
- Không nhóm khi đang ở Space Map / màn Pinax (không có danh sách).

## 2. Lệnh trên path bar

### Core — `Sources/PinaxCore/Browse/PathCommand.swift` (thuần, có test)
```swift
public struct PathCommand: Equatable, Sendable {
    public enum Target: Equatable, Sendable { case apps([String]) /* bundle id theo ưu tiên */, terminal, finder }
    public let name: String      // tên lệnh đã chuẩn hoá (lowercase)
    public let target: Target
    public let argument: String? // nil hoặc "." = thư mục đang xem
    public static let known: [(name: String, target: Target)]
    /// `forced` = có tiền tố ">". Không có ">" chỉ nhận dạng khi từ đầu là lệnh đã biết VÀ có đúng một đối số (vd "code .").
    public static func parse(_ text: String) -> PathCommand?
    /// Hoàn thành tên lệnh cho Tab khi text bắt đầu bằng ">": trả tên lệnh khớp tiền tố, sắp tên.
    public static func completions(_ text: String) -> [String]
}
```
- Lệnh: `code` (com.microsoft.VSCode, com.microsoft.VSCodeInsiders), `cursor` (com.todesktop.230313mzl4w4u92), `zed` (dev.zed.Zed, dev.zed.Zed-Preview), `subl` (com.sublimetext.4, com.sublimetext.3), `xed`/`xcode` (com.apple.dt.Xcode), `nova` (com.panic.Nova), `bbedit` (com.barebones.bbedit), `idea` (com.jetbrains.intellij, com.jetbrains.intellij.ce), `pycharm` (com.jetbrains.pycharm, com.jetbrains.pycharm.ce), `webstorm` (com.jetbrains.WebStorm), `studio` (com.google.android.studio), `fork` (com.DanPristupov.Fork), `tower` (com.fournova.Tower3), `term`/`terminal` (.terminal = Terminal đã chọn trong Settings), `iterm` (com.googlecode.iterm2), `warp` (dev.warp.Warp-Stable), `ghostty` (com.mitchellh.ghostty), `finder` (.finder).
- `parse`: trim; ">" đầu → bỏ, trim tiếp, rỗng → nil; từ đầu (lowercase) phải trong `known` không thì nil. Phần còn lại trim làm argument (rỗng → nil). Không có ">": chỉ nhận khi từ đầu là lệnh đã biết và có đối số không rỗng (tránh nuốt tên thư mục như "zed").
- Test `PathCommandTests.swift`: `code .`, `>code`, `> Code  ~/x`, `>unknown` → nil, `zed` (không ">", không đối số) → nil, `code` thư mục tên "code" không bị coi là lệnh khi không có đối số, `>` → nil, completions(">c") chứa code, cursor; completions("x") → [].

### App
- `BrowserModel.go(toPath:)` giữ nguyên. Thêm file mới `Sources/Pinax/Browser/BrowserModel+Commands.swift`: `func runPathCommand(_ text: String) -> Bool?` — nil nếu không phải lệnh; true nếu chạy được; false nếu là lệnh nhưng không chạy được (toast lý do).
  - Đích: argument nil/"." → `folder`; còn lại giải như `go(toPath:)` (~, tương đối theo `folder`); không tồn tại → toast "No such path"/"Không có đường dẫn này", false.
  - `.apps(ids)`: id đầu tiên có `NSWorkspace.urlForApplication(withBundleIdentifier:)` → `NSWorkspace.shared.open([url], withApplicationAt:configuration:)`; không có app nào → toast "\(tên) is not installed"/"Chưa cài \(tên)", false.
  - `.terminal` → `ExternalApps.terminal` (không có → toast, false). `.finder` → `NSWorkspace.shared.activateFileViewerSelecting([url])`.
  - Không bao giờ dùng `Process`, shell, AppleScript.
- `PathBar` / `PathField`: onSubmit: nếu text bắt đầu ">" → chỉ thử lệnh (kết quả nil = lệnh lạ → toast "Unknown command"/"Lệnh không rõ", trả false để ô lắc). Không có ">" → `go(toPath:)` trước; thất bại thì thử `runPathCommand`; nil → false. Chạy lệnh xong → đóng ô (`pathEditing = false`), không điều hướng.
- Tab khi text bắt đầu ">": dùng `PathCommand.completions`; một kết quả → điền `>tên `; nhiều → xoay vòng như đường dẫn và hiện danh sách gợi ý (cơ chế `onSuggestions` sẵn có). Icon bên trái đổi sang `terminal` (SF Symbol) khi text bắt đầu ">".
- GUIDE: mục "Lệnh trên path bar" liệt kê lệnh.

## 3. Chia việc
| Bước | Việc | File chính |
|---|---|---|
| A | §1 Nhóm (core + app) | mới `PinaxCore/Browse/FileGrouping.swift`, test; `BrowserPrefs.swift`, `BrowserModel.swift`, `FileListView.swift`, `IconGridView.swift`, `BrowserWindow.swift`, `PinaxApp.swift` (View menu) |
| B | §2 Lệnh path bar (core + app) | mới `PinaxCore/Browse/PathCommand.swift`, test; mới `Browser/BrowserModel+Commands.swift`, `PathBar.swift`, `PathField.swift` |
| C | Opus review, QA ảnh chụp, docs, 0.9.0 |

A và B không sửa chung file. B không sửa `BrowserModel.swift` (chỉ extension ở file mới).

## 4. Cổng hoàn thành
1. `swift test` xanh; grep an toàn vẫn 4 dòng; không có `Process(` mới.
2. Ảnh chụp: list nhóm theo Loại và theo Ngày (header nổi khi cuộn), icon view có nhóm, ô ⌘L ở chế độ lệnh.
3. Release như các bản trước.
