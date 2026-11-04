# M2 — File browser (v0.2.0)

> Mục tiêu: Pinax thành một trình duyệt file dùng hằng ngày được, chạy song song Finder.
> M1 (Smart Clean / Tidy / History) giữ nguyên, trở thành một mục trong sidebar của trình duyệt.

## 0. Kết quả spike "thay Finder" (2026-11-04, macOS 27.0)

| Cách | Kết quả |
|---|---|
| `NSWorkspace.setDefaultApplication(at:toOpen: .folder)` | Lỗi `NSCocoaErrorDomain 256` / `paramErr -50`, Finder giữ nguyên |
| `LSSetDefaultRoleHandlerForContentType("public.folder", .all, …)` | `-50`, Finder giữ nguyên |
| `defaults write -g NSFileViewer <bundle-id>` rồi gọi `activateFileViewerSelecting` và `selectFile(_:inFileViewerRootedAtPath:)` từ một process khác | App thử không nhận Apple Event nào và không được launch |

Chưa thử được (bị chặn quyền trong phiên, ghi lại để không khẳng định quá mức):
- `LSSetDefaultRoleHandlerForContentType` với role `.viewer` cho `public.folder` / `public.directory`.
- `NSFileViewer` khi app viewer **đang chạy sẵn** trước khi gọi.

**Kết luận cho M2:** không làm "đặt làm trình duyệt mặc định". Thay bằng các lối vào ở §6 (phím tắt toàn cục, Services, Open With, URL scheme, `open -a`). Nếu sau này thử lại được hai mục còn treo và chạy được → thêm ở bản sau.

## 1. Phạm vi

**Trong M2 (0.2.0):**
- Cửa sổ trình duyệt: sidebar, danh sách (list) + lưới (icon), điều hướng, path bar có git, ⌘L gõ đường dẫn có Tab completion, status bar.
- Thumbnail thật, Quick Look (Space), kích thước thư mục tính nền, ẩn/hiện file ẩn (⇧⌘.).
- Tự làm mới khi thư mục đang xem thay đổi.
- Tab cửa sổ (⌘T) bằng tabbing gốc của macOS.
- Thao tác file **tối thiểu**: mở / Open With, New Folder (⇧⌘N), Rename (Return), Move to Trash (⌘⌫), Copy Path (⌥⌘C), Show in Finder. Tất cả đi qua `Executor` + journal → Hoàn tác được.
- Mở thư mục hiện tại trong Terminal (⌥⇧⌘T) / Editor (⌥⇧⌘E).
- Lối vào: phím tắt toàn cục, Services "Open in Pinax", Pinax trong "Open With" cho thư mục, `pinax://open?path=`, `open -a Pinax <dir>`.

**Ngoài M2 (để M3):** copy/move giữa các thư mục, hàng đợi copy + tiến độ, hộp thoại trùng tên, kéo thả, cut/copy/paste qua lại với Finder, dual pane, Workspaces, lệnh `code .` trong path bar, Finder Sync extension (cần appex + sandbox).

## 2. Quyết định chốt

| Hạng mục | Quyết định |
|---|---|
| Vỏ app | Cửa sổ **trình duyệt là cửa sổ chính** (`WindowGroup`, mỗi tab/cửa sổ có `BrowserModel` riêng). Sidebar có 3 nhóm: **Favorites**, **Locations**, **Pinax** (Smart Clean, Downloads Tidy, History). Chọn mục Pinax thì vùng nội dung hiện màn M1 tương ứng. |
| Settings | Chuyển sang scene `Settings` chuẩn (⌘,). Mục Settings trong sidebar bị bỏ. |
| List / grid | `NSTableView` và `NSCollectionView` bọc bằng `NSViewRepresentable`. **Không** dùng SwiftUI `List`/`LazyVGrid` cho danh sách file. |
| Quick Look | Modifier SwiftUI `.quickLookPreview(_:in:)`, không tự nối `QLPreviewPanel`. |
| Live refresh | `DispatchSource.makeFileSystemObjectSource` (`.write`) trên fd của thư mục đang xem, debounce 200 ms. Không dùng FSEvents ở M2. |
| Thumbnail | `QLThumbnailGenerator`, cache theo (URL, mtime, size, scale), huỷ request khi cell bị tái dùng/cuộn qua. Cache bộ nhớ (NSCache), không ghi đĩa. |
| Kích thước thư mục | Tính nền bằng `SizeCalculator` hiện có, giới hạn 2 tác vụ song song, cache theo (URL, mtime), huỷ khi rời thư mục. |
| Git | Chỉ đọc. Chỉ chạy khi `xcode-select -p` thành công (nếu không, gọi `/usr/bin/git` sẽ bật hộp thoại cài Command Line Tools). Tìm `.git` bằng cách đi ngược lên cha. Lệnh `git -C <dir> status --porcelain=v2 --branch --untracked-files=normal`, timeout 3 s, debounce 500 ms theo repo, không bao giờ chạy theo từng phím gõ trong ⌘L. |
| Lõi vs UI | Logic duyệt (lister, watcher, git parser, path completion, file ops, ranking app editor/terminal) ở `PinaxCore` có test. `Pinax` chỉ chứa UI. Chuỗi hiển thị qua `L()`. |
| Phiên bản | 0.2.0 khi M2 xong. |

## 3. Hợp đồng an toàn — mở rộng cho trình duyệt

Giữ nguyên toàn bộ §1 của M1 (chỉ `trashItem`, xác thực lại, không theo symlink khi quét, lỗi từng item không phá batch, ghi journal trước khi báo xong). Bổ sung:

1. **Duyệt không giới hạn, thao tác có giới hạn.** Trình duyệt được *xem* mọi nơi đọc được (`/`, `/Volumes/*`, iCloud…). Thao tác ghi (rename, new folder, trash) phải qua `PathGuard`.
2. **PathGuard mới** (thêm, không nới phần cũ):

   | Vị trí | Thao tác ghi |
   |---|---|
   | Bên trong `~` (trừ danh sách cấm cũ) | Cho phép |
   | Bên trong `/Applications` (không phải gốc) | Cho phép (app Apple / Pinax vẫn bị chặn) |
   | Bên trong một volume ngoài `/Volumes/<tên>/…` (không phải gốc volume, không phải volume khởi động) | **Mới: cho phép** |
   | Gốc `/Volumes/<tên>` | Cấm |
   | `/`, `/System`, `/Library`, `/usr`, `/bin`, `/sbin`, `/private`, `/opt`, `/cores` và mọi thứ bên trong | Cấm |
   | `~/.Trash` và bên trong | Cấm |

   "Volume ngoài" = `URLResourceKey.volumeIsInternalKey == false` hoặc `volumeIsRemovableKey == true`, và không phải volume khởi động. Thêm test cho từng dòng (giả lập bằng root tiêm vào, không cần ổ thật).
3. **Rename** = `.move(from, to)` trong journal; không bao giờ ghi đè đích (đích tồn tại → báo lỗi, không đổi). Tên mới không được chứa `/` hay `:`, không rỗng, không là `.`/`..`.
4. **New Folder** = `.createDir`. Tên mặc định `untitled folder`, trùng thì `untitled folder 2`…
5. **Move to Trash** dùng `Executor.perform(candidates:)` y như Smart Clean (fingerprint đọc ngay lúc bấm).
6. Journal: thêm case enum vào `JournalOp` (nếu cần) là tương thích ngược với `journal.json` cũ (Codable tổng hợp chỉ thất bại với case lạ, không với case mới). Phải có test giải mã một `journal.json` mẫu của 0.1.x.
7. Lệnh grep an toàn (`grep -rn "removeItem\|trashItem" Sources`) sau M2 vẫn chỉ ra đúng 2 chỗ cũ.

## 4. PinaxCore — module `Browse/`

- `FileItem`: url, name, isDirectory, isPackage, isHidden, isSymlink, size (file), modified, created, kindDescription (`localizedTypeDescription`), contentType (`UTType?`), isAlias, tagNames (`tagNamesKey`), ubiquitous status.
- `DirectoryLister.list(_ url, showHidden) async throws -> [FileItem]`: một lần `contentsOfDirectory(includingPropertiesForKeys:)` với đủ key, không đệ quy, không theo symlink. Huỷ được.
- `FileSort`: theo name (localizedStandardCompare, thư mục trước — tuỳ chọn), modified, size, kind; tăng/giảm.
- `DirectoryWatcher`: wrap DispatchSource như §2, callback debounce; tự dừng khi deinit; xử lý thư mục bị xoá/đổi tên (đóng fd, báo `.vanished`).
- `GitStatus`: parser thuần cho output porcelain v2 (`# branch.head`, `# branch.ab +A -B`, dòng `1`/`2`/`u`/`?`) → `GitSummary { branch, detached, ahead, behind, staged, modified, untracked, conflicted }`. `GitStatusReader` chạy process (dùng `ProcessRunner` có sẵn), kiểm `xcode-select -p` một lần mỗi phiên, timeout, trả nil khi không phải repo.
- `PathCompletion.complete(_ typed: String, home: URL) -> [String]`: mở rộng `~`, chia phần cha + tiền tố, liệt kê thư mục con khớp tiền tố (không phân biệt hoa thường), tối đa 50, chỉ thư mục.
- `FileOps`: `newFolder(in:) `, `rename(_:to:)`, `trash(_ items:)` — mỏng, gọi `Executor`, trả `PerformResult`.
- `AppCatalog`: danh sách bundle id Terminal (`com.apple.Terminal`, `com.googlecode.iterm2`, `dev.warp.Warp-Stable`, `com.mitchellh.ghostty`) và Editor (`com.microsoft.VSCode`, `com.todesktop.230313mzl4w4u92` (Cursor), `dev.zed.Zed`, `com.apple.dt.Xcode`, `com.sublimetext.4`, `com.panic.Nova`, `com.barebones.bbedit`, JetBrains: `com.jetbrains.intellij`, `com.jetbrains.pycharm`, `com.jetbrains.WebStorm`, `com.google.android.studio`) — chỉ trả app thực sự có trên máy (`NSWorkspace.urlForApplication(withBundleIdentifier:)` — gọi ở tầng app, core nhận closure resolve để test được).

Test bắt buộc: lister (file ẩn, symlink, package, sort), watcher (tạo file → callback trong 1 s; xoá thư mục → `.vanished`), git parser (≥5 fixture: clean, ahead/behind, detached, untracked+modified+staged, conflict), git reader trên repo tạm (`git init` trong temp, bỏ qua test nếu `xcode-select -p` thất bại), path completion, PathGuard bảng §3.2, rename/newFolder/trash + undo, giải mã journal 0.1.x.

## 5. Pinax app — trình duyệt

**Cửa sổ** (`BrowserWindow`): `NavigationSplitView`.
- **Sidebar:** Favorites mặc định Home, Desktop, Documents, Downloads, Applications, iCloud Drive (nếu có `~/Library/Mobile Documents/com~apple~CloudDocs`); thêm/bỏ/sắp xếp lại được (kéo thả trong sidebar, lưu UserDefaults). Locations: các volume đang mount (`mountedVolumeURLs`, cập nhật theo `NSWorkspace.didMount/didUnmount`), có nút Eject cho volume ngoài. Nhóm Pinax: Smart Clean, Downloads Tidy, History.
- **Toolbar:** Back/Forward (⌘[ ⌘]), Enclosing folder (⌘↑), chuyển List/Icons (⌘1/⌘2), cỡ icon S/M/L (⌘+/⌘−), ô tìm trong thư mục hiện tại (lọc theo tên, không đệ quy).
- **Path bar** dưới toolbar: breadcrumb bấm được; bên phải hiện git `⎇ main ↑1 ↓0 · 3 thay đổi` khi trong repo. ⌘L biến path bar thành ô gõ: Tab = hoàn thành, Return = đi, Esc = huỷ; gõ đường dẫn file → mở thư mục chứa và chọn file.
- **List view:** cột Name (icon nhỏ + tên), Date Modified, Size (thư mục: kích thước nền, hiện "…" khi đang tính), Kind. Bấm header để sort. Multi-select. Double-click/⌘↓ mở (thư mục → vào, file → `NSWorkspace.open`). Return = rename tại chỗ. Space = Quick Look. Type-to-select.
- **Icon view:** thumbnail thật, thư mục hiện số mục + kích thước, 3 cỡ.
- **Status bar:** "N mục, M đã chọn · X trống".
- **Context menu:** Open, Open With ▸ (danh sách `urlsForApplications(toOpen:)`), Quick Look, Rename, New Folder, Move to Trash, Copy Path, Show in Finder, Open in Terminal, Open in Editor.
- **Trạng thái:** nhớ thư mục, view mode, sort, kích thước cột cho từng cửa sổ; mở lại app → khôi phục cửa sổ cuối.
- **Hoàn tác:** rename / new folder / trash ghi journal; ⌘Z đi qua `AppEnvironment.undo` như M1; History hiện cả các batch này.
- Lỗi quyền khi mở thư mục (TCC) → màn rỗng có lời giải thích + nút mở System Settings, không crash.

## 6. Lối vào Pinax (thay cho "trình duyệt mặc định")

1. **Info.plist `CFBundleDocumentTypes`:** `public.folder`, role Viewer, rank `Alternate` → Pinax xuất hiện trong Finder ▸ Open With cho thư mục, và `open -a Pinax ~/Downloads` chạy. App xử lý `application(_:open:)` → mở cửa sổ/tab tại thư mục đó (file → mở thư mục chứa, chọn file).
2. **URL scheme** `pinax://open?path=<percent-encoded>` (`CFBundleURLTypes`) — cho Raycast/Alfred/Shortcuts. Đường dẫn không tồn tại → mở Home kèm thông báo.
3. **Services:** `NSServices` "Open in Pinax" nhận `NSFilenamesPboardType`/file URL → hiện trong Finder ▸ chuột phải ▸ Services / Quick Actions.
4. **Phím tắt toàn cục:** Carbon `RegisterEventHotKey` (không cần quyền Accessibility). Mặc định ⌥⌘P, đổi được trong Settings (bộ ghi phím đơn giản), tắt được. Bấm → đưa Pinax lên trước, mở cửa sổ mới nếu chưa có.
5. **Dòng lệnh:** README hướng dẫn `open -a Pinax .` và alias `alias pinax='open -a Pinax'`. Không cài shim vào `/usr/local/bin` ở M2.
6. **Open in Terminal / Editor:** Settings chọn app từ `AppCatalog` (chỉ app có trên máy); mở bằng `NSWorkspace.open([folder], withApplicationAt:)`.

## 7. Chia việc

| Bước | Việc | Phụ thuộc |
|---|---|---|
| A | PinaxCore `Browse/` + PathGuard mới + journal compat + toàn bộ test §4 | — |
| B | Vỏ app mới: BrowserWindow, sidebar 3 nhóm (gắn màn M1 vào), Settings scene, list view NSTableView, điều hướng, path bar + ⌘L, status bar, watcher, khôi phục trạng thái, tab | A |
| C | Icon view NSCollectionView + thumbnail cache + kích thước thư mục + Quick Look | B (song song với D nếu không đụng file chung) |
| D | Thao tác file tối thiểu + context menu + Open With + Open in Terminal/Editor + git ở path bar | B |
| E | Lối vào §6 (document types, URL scheme, Services, hotkey) + Settings tương ứng | B |
| F | Opus review → sửa → QA §8 → docs → 0.2.0 release | C, D, E |

## 8. Kiểm chứng (cổng hoàn thành)

1. `swift build`, `swift test` xanh; grep an toàn không đổi.
2. **Hiệu năng:** script tạo thư mục tạm 10 000 file → mở trong Pinax, danh sách hiện < 300 ms (đo bằng log signpost hoặc thời gian in ra ở bản debug), cuộn mượt, icon view không treo khi thumbnail đang tải.
3. Chụp màn hình và tự nhìn: list, icon, path bar có git (mở repo Pinax), ⌘L đang gõ có gợi ý, sidebar Locations, Smart Clean nằm trong sidebar, Settings.
4. Thử thật trên thư mục tạm trong home: New Folder → Rename → Move to Trash → ⌘Z ba lần → mọi thứ về như cũ.
5. Nếu có ổ ngoài: rename trong `/Volumes/<ổ>/…` chạy, rename gốc volume bị chặn. Không có ổ ngoài → ghi rõ "chưa kiểm trên ổ thật", chỉ có test.
6. `open -a Pinax ~/Downloads`, `open "pinax://open?path=$HOME/Documents"`, Services trong Finder, phím tắt toàn cục: mỗi cái mở đúng thư mục.
7. Build release `./build.sh dmg`, mở bản release, cập nhật CHANGELOG/GUIDE/README/AGENTS (repo map), tag `v0.2.0`.
