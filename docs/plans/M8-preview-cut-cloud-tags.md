# M8 — Khung xem trước, ⌘X, Cloud + Tag trên sidebar (v0.8.0)

> Bù các chỗ thua FileOS (fileosmac.com): preview pane, cắt/dán, Google Drive / Dropbox trên sidebar, tag màu.
> Không đụng Executor / PathGuard / Transfer core. Mọi thao tác file vẫn qua đường cũ.

## 1. Khung xem trước (Preview pane)

- View > Show Preview / Hide Preview, phím **⇧⌘P** (như Finder). Lưu bật/tắt trong UserDefaults `pinax.browser.preview`. Nút trên toolbar (`sidebar.right`).
- SwiftUI `.inspector(isPresented:)` gắn ở detail của `BrowserWindowView`; width 260…480 (mặc định 320). Ẩn khi `model.pinax != nil`. Theo pane active (dual).
- Nội dung (theo vùng chọn của pane active; không chọn gì → thư mục đang xem):
  - **Một file / package**: `QLPreviewView` (Quartz, style `.compact`, `NSViewRepresentable`, đặt `previewItem` = URL; video phát được, PDF lật trang) cao ~ 55 %; dưới là tên (chọn được chữ), Kind, Size, Created, Modified, Tags (chấm màu), đường dẫn thư mục cha (bấm để mở).
  - **Một thư mục**: icon lớn, tên, số mục + dung lượng (dùng `folderSizes` của model, đang tính → "…"), Modified, và **nội dung hai cấp**: danh sách con trực tiếp (tối đa 30, thư mục trước, sắp tên) — mỗi thư mục con có thể mở rộng một cấp (tối đa 20 mục), đọc ngoài main bằng `DirectoryLister`/`FileManager`, bỏ mục ẩn trừ khi `showHidden`. Double-click một dòng = điều hướng tới đó (thư mục) / mở (file).
  - **Nhiều mục**: "N items" + tổng dung lượng file (thư mục tính khi có trong `folderSizes`), icon chồng của tối đa 3 mục đầu.
- Cập nhật theo vùng chọn có debounce 120 ms; huỷ đọc cũ khi đổi chọn. Không chạy QLPreviewView cho file > 2 GB không phải video/ảnh (chỉ hiện icon + metadata) — tránh treo.
- QA: `PINAX_QA_PREVIEW=1` → cửa sổ đầu bật preview; kết hợp `PINAX_OPEN=<file>` (đã chọn sẵn file) để chụp.

## 2. Cắt / dán (⌘X)

- Edit > Cut (⌘X) trên bảng / lưới: ghi URL lên pasteboard như ⌘C và ghi nhớ "cut" toàn app: `ClipboardCut.shared = (changeCount: NSPasteboard.general.changeCount, paths: Set<String>)`.
- ⌘V trong Pinax: nếu `changeCount` hiện tại == changeCount đã nhớ → **chuyển** (như ⌥⌘V) rồi xoá trạng thái cut; ngược lại chép như cũ. ⌥⌘V vẫn luôn chuyển.
- Mục đang bị cut hiện mờ (alpha 0.5) trong list và icon view cho tới khi dán / pasteboard đổi (kiểm `changeCount` khi vẽ).
- Dán vào Finder sau ⌘X của Pinax: Finder chép (Finder không có cut cho file) — ghi trong GUIDE.
- Text field đang sửa: ⌘X vẫn là cắt chữ (responder chain tự lo vì `cut:` chỉ cài trên subclass bảng / lưới).
- Bật/tắt: Cut như Copy nhưng thêm điều kiện mọi mục `fileOps.canModify`.

## 3. Sidebar: Cloud

- Section **Cloud** (chỉ hiện khi có mục): các thư mục con của `~/Library/CloudStorage` (`GoogleDrive-<email>`, `Dropbox`, `OneDrive-<tên>`, `Box-…`, …). Tên hiển thị: phần trước dấu "-" ánh xạ "GoogleDrive" → "Google Drive", "OneDrive" → "OneDrive", "Dropbox" → "Dropbox", "Box" → "Box"; phần sau (email / tổ chức) là `.help` và hiện mờ nếu có nhiều tài khoản cùng dịch vụ. iCloud Drive giữ ở Favorites như cũ.
- Core thuần `CloudLocations.list(root:) -> [CloudLocation{url, service, account}]` (tiêm root để test). App nạp lại khi app active (`NSApplication.didBecomeActiveNotification`).
- Kéo thả file lên mục Cloud như Favorite (dùng lại `drop(_:onto:)`).

## 4. Sidebar: Tag

- Section **Tags**: 7 màu chuẩn theo thứ tự Finder (Red, Orange, Yellow, Green, Blue, Purple, Gray) với tên đã bản địa hoá lấy từ `NSWorkspace.shared.fileLabels` (chỉ số 6,7,5,2,4,3,1) và chấm màu `fileLabelColors`.
- Bấm một tag → pane hiện mọi file mang tag đó trong home (Spotlight: `kMDItemUserTags == "<tên>"`, scope `NSMetadataQueryUserHomeScope`), hiển thị như kết quả tìm Subfolders (cột Where tương đối so với home, cùng luật bật/tắt thao tác của `.subfolders`). Tiêu đề cửa sổ = tên tag. Điều hướng đi nơi khác = thoát chế độ tag. Sidebar tô chọn tag đang xem.
- Gắn tag: context menu có hàng "Tags" với 7 chấm màu (toggle; chấm có dấu ✓ nếu mọi mục chọn đều có tag đó). Ghi bằng `URL.setResourceValues` / `NSURL.setResourceValue(_:forKey: .tagNamesKey)` cho từng mục; chỉ mục `fileOps.canModify`. Không vào journal (metadata, bấm lại là bỏ) — ghi rõ trong ARCHITECTURE "tag không qua Executor vì không đổi nội dung / vị trí".
- Cột list hiện chấm tag cạnh tên nếu `FileItem.tagNames` có (listing không đọc tag → đọc nền cho các dòng đang hiện, như ThumbnailLoader; hoặc bỏ phần chấm trong bảng nếu tốn — ưu tiên đúng và nhanh).

## 5. Chia việc
| Bước | Việc | File chính |
|---|---|---|
| A | §1 Preview pane | mới `Browser/PreviewPane.swift`; `BrowserWindow.swift` (inspector, toolbar, QA); `PinaxApp.swift` (View menu) |
| B | §2 Cut + §3 Cloud + §4 Tag | `FileListView.swift`, `IconGridView.swift`, `TransferActions.swift`, `BrowserMenu.swift`, `SidebarView.swift`, `BrowserModel.swift`, mới `PinaxCore/Browse/CloudLocations.swift`, `PinaxApp.swift` (Edit menu nếu cần) |
| C | Opus review, QA ảnh chụp, docs, 0.8.0 |

A không sửa file của B và ngược lại, trừ `PinaxApp.swift` (A: View menu, B: Edit menu) — đọc lại file ngay trước khi sửa.

## 6. Cổng hoàn thành
1. `swift test` xanh: test `CloudLocations` (tên, nhiều tài khoản, thư mục rỗng / không tồn tại), test trạng thái cut (changeCount khớp / lệch) nếu tách được logic thuần.
2. Ảnh chụp: preview một ảnh / PDF, một thư mục (hai cấp), nhiều mục; sidebar có Tags (+ Cloud nếu máy có); kết quả một tag; mục bị cut hiện mờ.
3. Release như các bản trước.
