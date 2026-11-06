# M5 — Space Map: cái gì đang chiếm chỗ (v0.5.0)

> Mục tiêu: quét một thư mục (mặc định Home), xem từng cấp cái gì nặng nhất, đi sâu vào, rồi đưa vào Thùng rác (hoàn tác được).
> Chỉ thêm mới: module core mới + một mục sidebar mới. Không đụng Transfer / Uninstall / PathGuard.

## 1. Phạm vi

**Trong M5:**
- Core `SpaceScanner` (fts(3)) dựng cây `SizeNode` với dung lượng thật trên đĩa (allocated).
- Màn **Space Map** (sidebar nhóm Pinax, sau Uninstall Apps): thanh tỉ lệ + danh sách con sắp theo dung lượng, breadcrumb, đi sâu / lên, Move to Trash (qua `Executor`), Reveal in Browser, Space = Quick Look.
- Context menu trình duyệt: "Analyze Size" (thư mục đang chọn hoặc thư mục đang xem) → mở Space Map và quét ở đó.
- Biến QA `PINAX_QA_SECTION=spaceMap`, `PINAX_QA_SPACEMAP=<thư mục>` (quét ngay thư mục đó khi mở).

**Ngoài M5:** treemap / sunburst (vẽ tay + hit-test), quét song song nhiều luồng, lưu kết quả quét qua lần mở app, quét `/` toàn ổ, so sánh hai lần quét.

## 2. Ngữ nghĩa dung lượng (core, có test)

- Dung lượng = `st_blocks * 512` (allocated, như "Size on disk"). File iCloud chưa tải (dataless) tự ra ~0 → không có gigabyte ảo.
- Không theo symlink (`FTS_PHYSICAL`), symlink tính 0 và không thành node.
- Không vượt sang ổ khác (`FTS_XDEV`): volume mount bên trong không bị tính.
- Hard link: file thường có `st_nlink > 1` chỉ tính một lần (tập `(st_dev, st_ino)`, chỉ lưu cho file nlink>1).
- Package (`.app`, `.photoslibrary`, `.bundle`…) là **lá**: dung lượng gồm toàn bộ bên trong, nhưng không có con. Nhận diện: thư mục có đuôi mở rộng **và** `URLResourceValues.isPackage == true` (chỉ hỏi khi có đuôi, cho rẻ).
- APFS clone bị tính hai lần (không có API rẻ để biết) → ghi rõ trong GUIDE.
- Bao gồm file ẩn (dotfile) — `~/.cache`, `~/.npm` thường rất nặng.
- File nhỏ hơn `minFileBytes` (mặc định 1 MB) không thành node riêng; gom vào một node `.others` mỗi thư mục ("N file nhỏ hơn"). Thư mục luôn có node (kể cả rỗng).
- Thư mục không đọc được (`FTS_DNR` / `FTS_ERR` / EPERM) → node `isUnreadable = true`, đếm vào `unreadableCount` của kết quả.

## 3. Chính sách quyền (TCC)

- `~/Library/Containers` và `~/Library/Group Containers`: **không đi vào** khi quét (đọc vào là macOS hỏi "truy cập dữ liệu của app khác"). Node được tạo với `skipped = true`, size 0, UI ghi "Not scanned · macOS asks permission" + nút "Scan" (người dùng chủ động) → quét riêng node đó (`scan(root:skip: [])`) rồi ghép vào cây.
- Danh sách bỏ qua tiêm được (`SpaceScanner.Options.skipPaths`), mặc định là hai đường dẫn trên tính từ home.
- Thư mục cần Full Disk Access (Mail, Messages, Safari, ~/.Trash…) trả EPERM im lặng → thành `isUnreadable`. Nếu `unreadableCount > 0`, UI hiện dòng "N folders couldn't be read" + nút mở Settings > Full Disk Access (dùng lại link Smart Clean đang dùng).
- Cổng ship: chạy quét Home thật một lần trên máy dev, chụp màn hình, xác nhận **không bật hộp thoại TCC nào**.

## 4. API core (`Sources/PinaxCore/Space/`)

```swift
public final class SizeNode: @unchecked Sendable {   // chỉ đọc khi đang quét; chỉ sửa trên main sau khi quét xong
    public enum Kind: Sendable { case directory, package, file, others }
    public let name: String            // tên thành phần cuối; node gốc = đường dẫn đầy đủ
    public let kind: Kind
    public internal(set) var size: Int64
    public internal(set) var fileCount: Int          // số file (đệ quy); others = số file được gom
    public internal(set) var children: [SizeNode]    // sắp theo size giảm dần sau khi quét xong
    public internal(set) var isUnreadable: Bool
    public internal(set) var skipped: Bool
    public internal(set) weak var parent: SizeNode?
    public var url: URL                               // dựng từ chuỗi parent (others → url của thư mục cha)
    public var isTrashable: Bool { kind != .others && parent != nil }
    /// Gỡ node khỏi cây, trừ size/fileCount ở mọi tổ tiên. Trả false nếu là gốc.
    @discardableResult public func removeFromParent() -> Bool
    /// Thay node `skipped` bằng kết quả quét mới (cùng url), cộng chênh lệch lên tổ tiên.
    public func replace(with scanned: SizeNode)
}

public struct SpaceScanner: Sendable {
    public struct Options: Sendable {
        public var minFileBytes: Int64 = 1_048_576
        public var skipPaths: Set<String>               // đường dẫn chuẩn hoá
        public static func defaults(home: URL) -> Options
    }
    public struct Progress: Sendable {
        public var files: Int; public var bytes: Int64; public var currentPath: String
        /// Các con trực tiếp của gốc đã quét xong: (tên, size, isDirectory)
        public var finishedTopLevel: [(name: String, size: Int64, isDirectory: Bool)]
    }
    public struct Result: Sendable { public let root: SizeNode; public let unreadableCount: Int; public let duration: TimeInterval }
    public init(options: Options)
    /// Ném CancellationError khi task bị huỷ (kiểm mỗi ~512 entry). `progress` gọi tối đa ~10 lần/s, trên luồng quét.
    public func scan(root: URL, progress: @Sendable (Progress) -> Void = { _ in }) throws -> Result
}
```

Cài đặt: `fts_open([root], FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil)`, dùng stack node theo `fts_level`. `FTS_D`: nếu trong skipPaths → tạo node skipped, `fts_set(FTS_SKIP)`; nếu là package → node `.package`, các entry bên trong chỉ cộng vào node package (không tạo con). `FTS_DP`: chốt node (sắp con, gắn node others nếu có), nếu `fts_level == 1` thêm vào `finishedTopLevel`. Size thư mục gồm `st_blocks` của chính nó.

## 5. App

- `SidebarSection.spaceMap` (title "Space Map" / "Bản đồ dung lượng", symbol `chart.bar.xaxis`), thứ tự: smartClean, downloads, uninstall, spaceMap, history.
- `SpaceMapModel` (@MainActor @Observable, trong `AppEnvironment`, dùng chung các cửa sổ như `UninstallModel`):
  - `state`: idle / scanning(progress) / done / failed(msg); `result`, `current: SizeNode?`, `treeVersion: Int` (tăng sau mỗi lần sửa cây để SwiftUI vẽ lại), `selection: Set<ObjectIdentifier>`.
  - `scan(_ url: URL)`: huỷ lượt cũ, `Task.detached(priority: .userInitiated)`; progress về main qua `Task { @MainActor }`, đã throttle trong core.
  - `cancel()`, `rescan()`, `open(node)` (đi sâu vào thư mục), `up()`, `jump(to:)` (breadcrumb), `scanSkipped(node)`.
  - `trashSelection()`: dựng `Candidate` (url, size, `FileFingerprint.read` ở nền, reason "Space Map", `.other`, preselected) → `confirmCandidates` → `ConfirmSheet` có sẵn → `Executor.perform` như `UninstallModel.confirmUninstall` → các mục `.done` thì `removeFromParent()`, toast có Undo, `history.reload()`, `onChanged` (Smart Clean refresh storage).
  - Mục bị PathGuard chặn (ngoài home / ổ ngoài) vẫn hiện, nhưng không chọn để xoá được (`isTrashable && PathGuard.isAllowed`).
- `SpaceMapView`:
  - Thanh trên: breadcrumb (bấm để nhảy), nút "Choose Folder…" (NSOpenPanel), "Scan Home", "Rescan".
  - Khi đang quét: số file + dung lượng đã đếm + đường dẫn hiện tại (rút gọn giữa) + Cancel; dưới là danh sách các con cấp 1 đã quét xong (sắp giảm dần).
  - Khi xong: thanh tỉ lệ ngang của `current` (8 con lớn nhất mỗi con một màu + "Other"), rồi bảng: icon, tên, thanh tỉ lệ so với con lớn nhất, size, %, số file. Double-click / Return vào thư mục = đi sâu; ⌘↑ = lên. Dòng skipped có nút "Scan"; dòng unreadable có chữ xám "Can't read".
  - Context menu dòng: Reveal in Browser (`model.navigate(to: parent, select: path)` ở pane active), Quick Look, Move to Trash, Analyze Here (quét lại với gốc là thư mục đó).
  - Space = Quick Look (`.onKeyPress(.space)` + `.quickLookPreview`, như UninstallView). ⌘⌫ = Move to Trash.
  - Trạng thái rỗng: mô tả ngắn + nút "Scan Home".
- Browser context menu (`BrowserMenu.make`): "Analyze Size" → `model.showPinax(.spaceMap)` + `env.spaceMap.scan(folderTarget)`.
- Chữ song ngữ dùng `L(en, vi)` như các màn khác.

## 6. An toàn

- Quét chỉ đọc. Xoá duy nhất qua `Executor.perform(candidates:)` + `FileManagerTrasher`; fingerprint đọc lại lúc bấm xác nhận. Lệnh grep an toàn không đổi (4 dòng).
- Không đi vào Containers / Group Containers nếu người dùng không bấm "Scan".

## 7. Chia việc

| Bước | Việc |
|---|---|
| A | Core `SizeNode`, `SpaceScanner` + test trên thư mục tạm (§8.1) + smoke `PINAX_SMOKE=1` quét home thật in thời gian, số file, 10 thư mục lớn nhất cấp 1, unreadableCount |
| B | App: `SidebarSection.spaceMap`, `SpaceMapModel`, `SpaceMapView`, context menu "Analyze Size", QA env vars (song song với A, theo API §4) |
| C | Opus review, quét Home thật + ảnh chụp, docs, 0.5.0 |

## 8. Cổng hoàn thành

1. `swift test` xanh; test: tổng đúng theo cây, hard link tính một lần, symlink bỏ qua, package là lá (size đủ, không có con), file nhỏ gom vào others, skipPaths → node skipped không đọc vào, thư mục chmod 000 → unreadable, huỷ → CancellationError, `removeFromParent` / `replace` cập nhật tổ tiên.
2. Smoke trên home thật: in thời gian quét, không treo. Đo thật: 2,4 triệu file, 76 s (release); `du -sxk ~` mất 94 s, tức là giới hạn ở đĩa, chấp nhận.
3. Ảnh chụp: đang quét, xong ở Home, đi sâu một cấp; không có hộp thoại TCC.
4. Release như các bản trước.
