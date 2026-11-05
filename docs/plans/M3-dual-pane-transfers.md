# M3 — Copy/Move, kéo thả, Dual Pane, Workspaces (v0.3.0)

> Mục tiêu: làm được mọi việc chép/chuyển file hằng ngày mà không phải mở Finder, và luôn hoàn tác được.
> Nền: M2 (trình duyệt, journal, PathGuard cho volume ngoài).

## 1. Phạm vi

**Trong M3 (0.3.0):**
- Lõi chép/chuyển (`Transfer`): copy, move cùng ổ, move khác ổ, duplicate; có tiến độ, huỷ được, xử lý trùng tên; ghi journal, ⌘Z hoàn tác.
- Hàng đợi chép (Transfers) có tiến độ + nút huỷ, hiện ở cuối cửa sổ.
- Clipboard kiểu Finder: ⌘C chép file (Finder dán được), ⌘V dán (cả file chép từ Finder), ⌥⌘V chuyển tới đây ("Move Item Here"), ⌘D Duplicate.
- Kéo thả: kéo ra (sang Finder/app khác), thả vào (từ Finder hoặc giữa các pane/cửa sổ Pinax) lên vùng trống, lên thư mục trong danh sách, lên Favorites.
- Dual Pane: hai khung trong một cửa sổ, mỗi khung có thư mục/lịch sử/vùng chọn riêng; F5 chép sang khung kia, F6 chuyển sang khung kia.
- Workspaces: lưu các tab của cửa sổ (kể cả dual pane) thành một workspace có tên; mở lại bằng một cú bấm ở sidebar.

**Ngoài M3:** spring-loaded folder, kéo thả lên path bar, hàng đợi chạy song song, merge thư mục khi trùng (Finder cũng không merge), đồng bộ thư mục, FTP/SMB riêng, Finder Sync extension.

## 2. Quyết định chốt

| Hạng mục | Quyết định |
|---|---|
| API chép | `copyfile(3)` với `COPYFILE_ALL \| COPYFILE_RECURSIVE \| COPYFILE_CLONE \| COPYFILE_NOFOLLOW` (APFS clone tức thì; symlink chép thành symlink, không theo). Callback trạng thái để báo tiến độ và huỷ (`COPYFILE_QUIT`). Không dùng `FileManager.copyItem` (không có tiến độ / huỷ). |
| Không bao giờ thấy nửa file | Chép vào tên tạm `.pinax-partial-<uuid>-<tên>` trong thư mục đích, xong mới `rename(2)` sang tên thật (`renamex_np` + `RENAME_EXCL`). Huỷ / lỗi → bản dở được đưa vào Thùng rác qua `Trasher` (không `removeItem`). |
| Move cùng ổ | `rename` (= `FileManager.moveItem`), journal `.move`. |
| Move khác ổ | Chép (như trên) → xong mới chuyển **nguồn vào Thùng rác**. Journal: `.copy` + `.trash`. Không bao giờ xoá vĩnh viễn nguồn. Không đưa được nguồn vào Thùng rác → giữ cả hai, báo "đã chép nhưng không gỡ được bản gốc". |
| Trùng tên | Hỏi **một lần cho cả lượt**: *Thay thế* / *Giữ cả hai* / *Bỏ qua* (+ Huỷ). Thay thế = đưa mục cũ vào Thùng rác (journal `.trash`) rồi mới chép/chuyển. Giữ cả hai = `tên 2.ext`, `tên 3.ext`. Duplicate/dán vào chính thư mục nguồn = `tên copy.ext`, `tên copy 2.ext`, không hỏi. |
| Chặn | Chép một thư mục vào chính nó / con của nó → bỏ qua (`.intoItself`). Thả lên chính nó → không làm gì. Đích phải qua PathGuard (như New Folder); nguồn của **move** phải qua PathGuard (như Rename); nguồn của **copy** chỉ cần đọc được (chép từ `/System` được). |
| Dung lượng | Move/copy khác ổ: tổng kích thước > dung lượng trống của ổ đích → từ chối cả lượt trước khi bắt đầu. Cùng ổ APFS không kiểm (clone). |
| Hàng đợi | Một hàng đợi toàn app, chạy **tuần tự** từng job. Mỗi job = một batch journal. Huỷ giữa chừng: các mục đã xong vẫn giữ và vẫn ghi journal (hoàn tác được), mục đang dở bị dọn như trên. |
| Kéo thả | Cùng ổ → move, khác ổ → copy; giữ ⌥ = copy, giữ ⌘ = move (giống Finder). Kéo **từ Pinax ra Finder**: Finder tự làm, không journal (ghi rõ trong GUIDE). Thả **vào Pinax** (từ đâu cũng vậy) đi qua `Transfer` → có journal. |
| Clipboard | ⌘C / ⌘V qua responder chain (`copy:` / `paste:` trên table/collection view) để ô chữ tự giữ ⌘C/⌘V của nó. Ghi lên pasteboard: `NSURL` file + tên file dạng chữ. ⌥⌘V và F5/F6 là mục menu riêng, dùng `TextEditing.forward` như ⌘⌫. |
| Dual pane | `WindowModel` giữ `panes: [BrowserModel]` (1 hoặc 2) + `activeIndex`. Lệnh menu, sidebar, toolbar luôn tác động lên pane đang active. View > "Dual Pane" (⌘\\). Pane active có viền nhấn (accent) ở path bar; bấm/focus vào pane nào thì pane đó active. Tab chuyển pane theo key-view loop. Màn M1 (Smart Clean/Tidy/History) chiếm cả vùng nội dung. |
| Workspaces | `Workspace { id, name, tabs: [TabState] }`, `TabState { left, right?, viewMode, active }`, lưu `~/Library/Application Support/Pinax/workspaces.json` (ghi atomic). Sidebar nhóm "Workspaces": bấm = mở cửa sổ mới với đủ tab; chuột phải: Rename, Update from Current Window, Delete (chỉ xoá preset, không đụng file). File > "Save Window as Workspace…" (⌃⌘S). |

## 3. Hợp đồng an toàn — bổ sung cho chép/chuyển

Giữ nguyên §1 của M1 và §3 của M2. Bổ sung:

1. Journal thêm case `JournalOp.copy(source: URL, created: URL)`. **Hoàn tác copy = đưa `created` vào Thùng rác** qua `Trasher` (không `removeItem`). `created` không còn → `.skipped(.missing)`.
2. Undo đi ngược thứ tự op như cũ, nên "Thay thế" (`.trash(cũ)` rồi `.copy`/`.move`) hoàn tác thành: gỡ bản mới → trả bản cũ từ Thùng rác về.
3. Không bao giờ ghi đè: mọi lần đặt tên cuối cùng dùng `RENAME_EXCL` / kiểm tra `lstat`; đích bị chiếm giữa chừng → mục đó `.skipped(.destinationExists)`.
4. Bản dở (`.pinax-partial-*`) chỉ do Pinax tạo, chỉ được dọn bằng `Trasher`. Lệnh grep an toàn vẫn chỉ ra 2 chỗ cũ (Trasher + removeIfEmpty).
5. Không theo symlink: symlink được chép/chuyển như chính nó.
6. Hàng đợi chạy ngoài main thread; journal được ghi trước khi UI báo xong (như M1 §1.7).
7. Test giải mã `journal.json` cũ (0.2.0, không có `.copy`) vẫn qua.

## 4. PinaxCore

- `Journal/Journal.swift`: thêm `.copy(source:created:)`; `SkipReason` thêm `.intoItself`, `.insufficientSpace`, `.cancelled`.
- `Journal/Executor.swift`: `undo(batch:trasher:)` (mặc định `FileManagerTrasher()`), xử lý `.copy`. Thêm `record(title:ops:outcomes:)` công khai (dùng `finish` hiện có) để `Transfer` ghi batch.
- `Browse/Transfer.swift` (mới):
  - `TransferKind { copy, move, duplicate }`, `ConflictPolicy { replace, keepBoth, skip }`.
  - `TransferPlan`: dựng từ `sources: [URL]`, `destination: URL`, kind → danh sách `TransferItem { source, target, conflict: Bool, crossVolume: Bool, skip: SkipReason? }`. Thuần, test được, không đụng đĩa ngoài `lstat`/resource values.
  - `availableName(for:in:style:)` với `.numbered` (`tên 2.ext`) và `.copySuffix` (`tên copy.ext`, `tên copy 2.ext`); thư mục/package không tách đuôi.
  - `TransferRunner.run(plan, policy, progress: (TransferProgress) -> Void, isCancelled: () -> Bool, trasher, executor, home, title) -> PerformResult`: thực thi theo §2, ghi một batch.
  - `CopyFile.copy(from:to:progress:isCancelled:) throws` bọc `copyfile` (state + `COPYFILE_STATE_STATUS_CB`, context qua `Unmanaged`).
  - `TransferProgress { completedBytes, totalBytes, currentName, completedItems, totalItems }`.
- Tests (`TransferTests`): đặt tên (cả hai kiểu, đuôi kép `.tar.gz` coi đuôi là `gz`, thư mục), plan (trùng tên, vào chính nó, move cùng thư mục = bỏ qua), copy file + thư mục lồng + symlink giữ là symlink, move cùng ổ, move khác ổ giả lập (tiêm `isSameVolume`), Replace → undo trả bản cũ, Keep Both, Skip, huỷ giữa chừng (bản dở vào Trasher giả, mục đã xong vẫn trong journal), undo copy → bản chép vào Trasher giả, PathGuard chặn đích/nguồn move, journal 0.2.0 giải mã được.

## 5. Pinax app

- `Transfers/TransferQueue.swift` (`@Observable`, singleton trong `AppEnvironment`): enqueue job, chạy tuần tự trong `Task.detached`, tiến độ cập nhật main ≤ 10 lần/giây, huỷ, kết quả → toast có Undo + thêm vào History.
- `Transfers/TransferStrip.swift`: dải ở đáy cửa sổ khi có job: tên job, thanh tiến độ, "x / y items", nút huỷ; ẩn khi rỗng.
- Hộp thoại trùng tên: `NSAlert` sheet trên cửa sổ đang active: "N items already exist in <thư mục>" + Replace / Keep Both / Skip / Cancel.
- Clipboard + menu Edit: Copy (⌘C, file), Paste (⌘V), Move Item Here (⌥⌘V), Duplicate (⌘D). File > Copy to Other Pane (F5), Move to Other Pane (F6) — chỉ bật khi dual pane.
- Kéo thả trong `FileListView` / `IconGridView`: `pasteboardWriterForRow`/item → `NSURL`; nhận drop lên hàng thư mục (highlight) và vùng trống; sidebar Favorites nhận drop (`.dropDestination`).
- Dual pane: `WindowModel` (mới) thay cho `BrowserModel` trực tiếp ở `BrowserRoot`; `focusedSceneValue(\.browser, active)`; `@SceneStorage` lưu thư mục pane 2 + trạng thái dual; `HSplitView` hai `BrowserContent`.
- Workspaces: `WorkspaceStore` (core, JSON, test được), sidebar section, sheet đặt tên, mở = `openWindow` từng tab (`BrowserSeed` thêm `secondPath`, `viewMode`).

## 6. Chia việc

| Bước | Việc | Phụ thuộc |
|---|---|---|
| A | Core: journal `.copy`, undo qua Trasher, `Transfer` (plan, đặt tên, CopyFile, Runner), `WorkspaceStore`, toàn bộ test §4 | — |
| B | App: TransferQueue + strip + hộp thoại trùng tên + clipboard/menu (⌘C/⌘V/⌥⌘V/⌘D) + context menu | A |
| C | Kéo thả: list, icon, Favorites | B |
| D | Dual pane: WindowModel, F5/F6, lưu trạng thái | B (có thể song song C nếu không đụng file chung — thực tế đụng FileListView, nên làm tuần tự) |
| E | Workspaces UI | D |
| F | Opus review → QA §7 → docs → 0.3.0 | tất cả |

## 7. Kiểm chứng (cổng hoàn thành)

1. `swift build`, `swift test` xanh; grep an toàn không đổi (2 chỗ).
2. Test chép thật trong thư mục tạm của test: thư mục 1 000 file + file 1 GB (chép khác thư mục trên APFS = clone, phải < 1 s); huỷ giữa chừng một bản chép không clone được (giả lập bằng cờ tắt clone) để soát dọn bản dở.
3. Chụp màn hình (không gửi phím ảo): dual pane, strip tiến độ (dùng biến QA `PINAX_QA_TRANSFER=<src>:<dst>` để tự khởi động một job khi mở app), sidebar Workspaces.
4. User thử tay: ⌘C trong Pinax → ⌘V trong Finder và ngược lại; ⌥⌘V; kéo từ Finder vào Pinax và ngược lại; F5/F6; trùng tên 3 lựa chọn; ⌘Z từng loại; mở workspace.
5. Ổ ngoài (nếu có): chuyển khác ổ → nguồn nằm trong Thùng rác, ⌘Z trả về. Không có ổ → ghi rõ "chỉ có test giả lập".
6. Release: VERSION 0.3.0, CHANGELOG/GUIDE/README/AGENTS, `./build.sh dmg`, chạy bản trong ZIP, tag `v0.3.0`, gh release.
