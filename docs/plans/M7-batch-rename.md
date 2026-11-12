# M7 — Đổi tên hàng loạt (v0.7.0)

> Mục tiêu: chọn nhiều mục → "Rename N Items…" → chọn kiểu đổi, xem trước tên mới từng dòng, bấm Rename. Cả lượt là một mục History, ⌘Z trả lại hết.
> Dùng lại `Executor.perform(moves:)` (PathGuard, không ghi đè, journal). Không đổi Executor / PathGuard.

## 1. Phạm vi

**Trong M7:** ba kiểu như Finder + đổi hoa/thường:
- **Replace Text**: tìm `find` thay bằng `replace` (mọi lần xuất hiện), tuỳ chọn phân biệt hoa/thường (mặc định không).
- **Add Text**: thêm `text` vào trước hoặc sau tên.
- **Format**: `base` + số thứ tự; số bắt đầu `start` (mặc định 1), đệm `digits` chữ số (mặc định 0 = không đệm, tối thiểu đủ cho số lớn nhất), vị trí số sau hoặc trước `base`, ngăn cách `separator` (mặc định " ").
- **Change Case**: lower / UPPER / Title Case.
- Mặc định chỉ đổi phần tên, giữ đuôi (`.jpg`); tuỳ chọn "Include extension" cho Replace / Change Case. Thư mục và package: "đuôi" chỉ tính khi là package (`.app`…) — thư mục thường coi toàn bộ là tên.
- Thứ tự đánh số = thứ tự đang hiển thị trong danh sách.

**Ngoài M7:** regex, đổi tên theo EXIF / ngày, lưu preset, đổi tên trên nhiều thư mục có cấu trúc.

## 2. Core (`Sources/PinaxCore/Browse/BatchRename.swift`)

```swift
public enum RenameRule: Equatable, Sendable {
    case replace(find: String, with: String, caseSensitive: Bool, includeExtension: Bool)
    case add(text: String, atEnd: Bool)
    case format(base: String, start: Int, digits: Int, numberFirst: Bool, separator: String)
    case changeCase(CaseStyle, includeExtension: Bool)
    public enum CaseStyle: Sendable { case lower, upper, title }
}

public struct RenameEntry: Equatable, Sendable {
    public let source: URL
    public let newName: String
    public let issue: Issue?
    public var target: URL { source.deletingLastPathComponent().appendingPathComponent(newName) }
    public enum Issue: Equatable, Sendable {
        case unchanged                 // tên mới == tên cũ → bỏ qua, không phải lỗi
        case invalid(FileNameError)    // FileOps.validatedName ném
        case duplicateInBatch          // hai mục cùng thư mục ra cùng tên (so không phân biệt hoa/thường)
        case exists                    // đích đã có trên đĩa và không phải một mục khác trong lượt (sẽ được dời đi), không phải đổi hoa/thường của chính nó
    }
}

public enum BatchRename {
    /// Áp rule cho từng tên (thuần, test được). `index` bắt đầu từ 0 theo thứ tự `urls`.
    public static func newName(for url: URL, index: Int, count: Int, rule: RenameRule, isPackage: Bool, isDirectory: Bool) -> String
    /// Dựng preview + kiểm tra (đọc đĩa bằng lstat để biết đích tồn tại).
    public static func plan(_ urls: [URL], rule: RenameRule) -> [RenameEntry]
    /// Có thể thực hiện: không mục nào có issue khác `.unchanged`, và ít nhất một mục đổi.
    public static func canApply(_ entries: [RenameEntry]) -> Bool
    /// Thứ tự move an toàn: nếu đích của một mục là nguồn của mục khác trong lượt (chuỗi / hoán đổi a↔b),
    /// mục đó đi hai bước qua tên tạm `.pinax-rename-<8hex>-<tên cũ>` cùng thư mục: mọi bước 1 trước, rồi mọi bước 2.
    /// Không có va chạm → một bước. Bỏ mục `.unchanged`.
    public static func moves(_ entries: [RenameEntry]) -> [(from: URL, to: URL)]
}
```

`FileOps.batchRename(_ entries: [RenameEntry], title: String) -> PerformResult` = `executor.perform(moves: BatchRename.moves(entries), createDirs: [], title:, home:)`. Journal ghi các move (kể cả bước tạm); undo đi ngược nên trả về đúng tên cũ.

Lưu ý `newName` cho Format: số = `start + index`, đệm `max(digits, 0)` chữ số; giữ đuôi gốc (file / package).
Title Case: viết hoa chữ cái đầu mỗi từ (tách theo khoảng trắng, `-`, `_`), phần còn lại viết thường; dùng `capitalized(with: nil)` nếu cho kết quả hợp lý.

Test: từng rule (kể cả tên không có đuôi, tên bắt đầu bằng ".", package `.app`, thư mục có dấu chấm trong tên), Unicode có dấu (NFC/NFD — so sánh tên theo `precomposedStringWithCanonicalMapping`), unchanged, invalid ("/" trong text, rỗng), duplicateInBatch (hoa/thường khác nhau vẫn trùng), exists, đổi hoa/thường của chính nó không phải exists, hoán đổi a↔b và chuỗi a→b→c chạy thật trên thư mục tạm qua `FileOps.batchRename` rồi `executor.undo` trả về đúng.

## 3. App

- `BrowserModel`: `canBatchRename` (≥ 2 mục chọn, `pinax == nil`, mọi mục `fileOps.canModify`), `beginBatchRename()` mở sheet. Return khi chọn ≥ 2 mục → mở sheet (một mục vẫn là đổi tên tại chỗ). Context menu: "Rename…" khi nhiều mục → "Rename N Items…" / "Đổi tên N mục…". Menu File: "Rename N Items…" (không phím tắt riêng).
- `BatchRenameSheet` (SwiftUI): Picker kiểu (Replace / Add / Format / Case) + các ô của kiểu đó; bảng xem trước hai cột (tên cũ → tên mới), dòng có issue tô đỏ kèm lý do ngắn, dòng unchanged màu phụ; tóm tắt "N will be renamed · M problems"; nút Rename (default, tắt khi `!canApply`), Cancel (Esc). Preview tính lại ngay khi gõ (plan chạy ngoài main nếu > 500 mục).
- Thực thi ngoài main → toast "Renamed N items" có Undo, `history.reload()`, chọn các mục mới (đường `reloadAfterOperation(select:)`), lỗi từng mục → toast problems như các thao tác khác. Đang tìm kiếm Subfolders: chạy lại tìm (đã có cơ chế sau thao tác).
- QA: `PINAX_QA_BATCH_RENAME=1` (cùng `PINAX_OPEN`): cửa sổ đầu, sau khi nạp xong, chọn mọi mục và mở sheet (kiểu Format, base "Photo").

## 4. An toàn
- Chỉ `moveItem` qua Executor; không ghi đè (Executor bỏ qua `.destinationExists`). Lệnh grep an toàn không đổi.
- Tên tạm bắt đầu bằng "." để ẩn; nếu bước 2 hỏng, file vẫn ở tên tạm và ⌘Z đưa về tên gốc.

## 5. Chia việc
| Bước | Việc |
|---|---|
| A | Core §2 + test |
| B | App §3 (song song theo API §2) |
| C | Opus review, QA ảnh chụp sheet + kết quả trên thư mục tạm, ⌘Z bằng journal, docs, 0.7.0 |

## 6. Cổng hoàn thành
1. `swift test` xanh với test §2 (hoán đổi + chuỗi + undo chạy thật).
2. Ảnh chụp sheet với preview đủ bốn kiểu; một lượt thật trên thư mục tạm và hoàn tác qua `Executor.undo`.
3. Release như các bản trước.
