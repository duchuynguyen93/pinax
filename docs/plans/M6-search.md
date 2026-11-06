# M6 — Tìm kiếm trong trình duyệt (v0.6.0)

> Mục tiêu: ⌘F để lọc thư mục đang xem ngay khi gõ, hoặc tìm theo tên trong mọi thư mục con. Kết quả hiện ngay trong bảng / lưới hiện có, thao tác trên kết quả như trên file thường (mở, Quick Look, kéo thả, chép, Trash, đổi tên).
> Trình duyệt hiện chưa có tìm kiếm nào. Không đụng Transfer / Executor / PathGuard.

## 1. Phạm vi

**Trong M6:**
- Ô tìm trên toolbar (`.searchable`), ⌘F đưa focus vào, Esc xoá và thoát tìm.
- Hai phạm vi (`.searchScopes`): **This Folder** (lọc danh sách đang có, tức thì) và **Subfolders** (tìm đệ quy trong thư mục đang xem).
- Khớp tên: không phân biệt hoa/thường **và dấu** ("tai lieu" khớp "Tài liệu"), nhiều từ = phải có đủ (AND), mỗi từ là "chứa".
- Subfolders: dùng Spotlight (`NSMetadataQuery`, phạm vi = thư mục đang xem) khi thư mục nằm trên ổ khởi động; trên ổ ngoài / ổ mạng dùng duyệt fts của Pinax (`NameSearch`). Kết quả đổ dần, tối đa 5 000 mục.
- Bảng kết quả có thêm cột **Where** (thư mục cha, rút gọn tương đối so với gốc tìm).

**Ngoài M6:** tìm theo nội dung file, theo tag / ngày / cỡ (bộ lọc nâng cao), tìm đã lưu (smart folder), tìm toàn máy, lịch sử tìm.

## 2. Core (`Sources/PinaxCore/Search/`)

```swift
/// Khớp tên theo các từ của câu tìm: bỏ hoa/thường + dấu (đ → d), mỗi từ phải là chuỗi con.
public struct NameMatcher: Sendable {
    public let terms: [String]                 // đã fold, bỏ rỗng
    public init(_ query: String)
    public var isEmpty: Bool
    public func matches(_ name: String) -> Bool
    /// Fold dùng chung: lowercased + bỏ dấu (CFStringTransform / folding(options: [.caseInsensitive, .diacriticInsensitive])) + "đ"/"Đ" → "d".
    public static func fold(_ s: String) -> String
}

/// Predicate Spotlight cho câu tìm: mỗi từ một điều kiện `kMDItemFSName LIKE[cd] "*từ*"`, nối AND.
/// Escape `\`, `"`, `*`, `?` trong từ. Trả nil khi câu tìm rỗng.
public enum SpotlightPredicate {
    public static func make(_ query: String) -> NSPredicate?
}

/// Duyệt fts tìm theo tên (dùng khi Spotlight không áp được). Chỉ đọc.
public struct NameSearch: Sendable {
    public struct Options: Sendable {
        public var includeHidden: Bool = false     // false: bỏ qua mục bắt đầu bằng "." và không đi vào thư mục ẩn
        public var limit: Int = 5000
        public var skipPaths: Set<String> = []     // không đi vào (Containers…)
    }
    public init(options: Options)
    /// Gọi `found` theo lô (≤ ~10 lần/s, kèm lô cuối). Không theo symlink (FTS_PHYSICAL), không vượt ổ (FTS_XDEV),
    /// không đi vào package (package vẫn có thể là kết quả). Gốc không tính là kết quả. Dừng ở `limit`.
    /// Ném CancellationError khi task bị huỷ. Trả về true nếu bị cắt ở limit.
    public func run(root: URL, matcher: NameMatcher, found: @Sendable ([URL]) -> Void) throws -> Bool
}
```

Test: fold ("Tài Liệu" → "tai lieu", "Đà" → "da"), nhiều từ AND, từ rỗng; predicate escape `"` và `*`; NameSearch: tìm ở nhiều cấp, bỏ ẩn khi includeHidden=false, có khi true, không vào package nhưng package khớp tên thì có, symlink không theo, limit cắt và trả true, skipPaths, huỷ.

## 3. App

### 3.1 Trạng thái trong `BrowserModel`
- `searchText: String`, `searchScope: SearchScope (.folder, .subfolders)`, `isSearching: Bool` (query không rỗng), `searchRunning: Bool`, `searchTruncated: Bool`.
- Giữ danh sách thư mục gốc ở `listed: [FileItem]`; `items` là cái đang hiển thị:
  - không tìm → `items = listed` (như cũ);
  - `.folder` → `items = listed.filter { matcher.matches($0.name) }` (làm lại mỗi khi gõ / nạp lại);
  - `.subfolders` → `items = results` (đã sắp theo `prefs.sort`).
- Gõ: debounce 200 ms cho `.subfolders`; `.folder` lọc ngay.
- Rời thư mục (`navigate`, back/forward/up, `showPinax`) → xoá tìm kiếm (như Finder). Mở một thư mục trong kết quả = điều hướng vào đó và thoát tìm.
- `.subfolders`:
  - Ổ khởi động (`volumeURL` của thư mục == `/`, hoặc `volumeIsRootFileSystem`): `SpotlightSearch` (lớp app, bọc `NSMetadataQuery` trên main, `searchScopes = [folder]`, predicate từ `SpotlightPredicate.make`, `enableUpdates` sau lần gom đầu để kết quả tự cập nhật khi file bị đổi tên / chuyển đi). Lọc lại bằng `NameMatcher` (Spotlight `[d]` không đổi "đ"), bỏ mục ẩn khi `prefs.showHidden == false`, bỏ chính thư mục gốc, cắt 5 000.
  - Ổ khác: `NameSearch` trong `Task.detached`, `skipPaths` = Containers / Group Containers của home.
  - URL → `FileItem` đọc ngoài main (như `DirectoryLister`), sắp bằng `prefs.sort`, cập nhật `items` theo lô (≤ 5 lần/s).
- Sau thao tác (trash, rename, paste, duplicate…) khi đang tìm `.subfolders`: Spotlight tự cập nhật; nhánh fts thì chạy lại tìm.
- Kích thước thư mục (`folderSizes.request`) không tự tính cho kết quả `.subfolders`.

### 3.2 Bật / tắt thao tác khi đang tìm `.subfolders`
- Tắt: New Folder, Paste, thả vào nền bảng (thả *lên* một thư mục trong kết quả vẫn được), Tidy Folder.
- Giữ: mở, Quick Look, chép (⌘C), kéo ra ngoài, Trash, đổi tên (⏎), Duplicate (tạo cạnh file gốc — nếu `enqueueTransfer` dùng `folder` làm đích thì Duplicate phải tắt trong `.subfolders`), Copy Path, Show in Finder, Analyze Size, F5/F6.
- `.folder`: mọi thứ như bình thường (vẫn là thư mục đang xem).

### 3.3 Giao diện
- `.searchable(text:placement: .toolbar, prompt: L("Search", "Tìm"))` trên detail của `BrowserWindowView`, bind vào pane active; ẩn / tắt khi `model.pinax != nil`.
- `.searchScopes`: "This Folder" / "Thư mục này", "Subfolders" / "Thư mục con". Đổi scope chạy lại tìm.
- ⌘F: menu Edit > Find (`.keyboardShortcut("f")`) đưa focus vào ô tìm (`.searchFocused` hoặc tương đương).
- Bảng: cột `where` (L("Where", "Vị trí")) chỉ hiện (`isHidden = false`) khi `.subfolders`; giá trị = đường dẫn thư mục cha tương đối so với gốc tìm ("." → tên gốc), dài thì cắt giữa.
- Status bar khi tìm: "N results for “q”" / "N kết quả cho “q”", thêm "· searching…" khi đang chạy, "· showing first 5,000" khi bị cắt.
- Không có kết quả: overlay `ContentUnavailableView.search(text:)`.
- Path bar giữ nguyên (vẫn là thư mục gốc tìm).

### 3.4 QA
- `PINAX_QA_SEARCH=<scope>:<query>` (scope = folder|subfolders): cửa sổ đầu tiên, một lần, đặt sẵn tìm kiếm sau khi thư mục nạp xong (dùng cùng `PINAX_OPEN`).

## 4. An toàn
- Tìm chỉ đọc. Mọi thao tác trên kết quả đi qua đường cũ (FileOps / Executor / TransferQueue), lệnh grep an toàn không đổi.
- Không đi vào Containers khi duyệt fts.

## 5. Chia việc

| Bước | Việc |
|---|---|
| A | Core §2 + test |
| B | App §3 (song song, theo API §2) |
| C | Opus review, QA bằng ảnh chụp (cả hai phạm vi, có chữ tiếng Việt có dấu), docs, 0.6.0 |

## 6. Cổng hoàn thành
1. `swift test` xanh với test §2.
2. Ảnh chụp: lọc This Folder; Subfolders trong `~/Code` có cột Where; tìm "tai lieu" ra file "Tài liệu…" (tạo file mẫu trong thư mục tạm của home, dọn sau).
3. Spotlight trả kết quả trong < 1 s cho `~` với từ phổ biến; không treo UI khi 5 000 kết quả.
4. Release như các bản trước.
