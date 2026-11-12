<p align="center"><img src="assets/AppIcon-1024.png" width="128" alt="Pinax icon"></p>

# Pinax

Pinax is a free, open-source, native SwiftUI utility for macOS that finds disk clutter and tidies your Downloads folder. It never deletes anything: every removal is a move to the Trash, and every batch can be undone from the built-in history. Later milestones will grow it into a Finder companion with its own file browser.

> Version 0.8.0 (M8). Apple Silicon only, macOS 26 or later. Ad-hoc signed, see [Install](#install).

## Features

- **File browser**: list and icon views, Quick Look, Go to Path with Tab completion, tabs, folder sizes, and a git-aware path bar (branch, ahead/behind, changes). New Folder, Rename and Move to Trash go through the same journal, so Cmd+Z undoes them. Open it from anywhere with Option+Cmd+P, Finder Services, Open With or `pinax://open?path=`.
- **Copy and move**: Cmd+C / Cmd+V (works with Finder), drag and drop, Duplicate, a progress strip with Stop, and a conflict prompt; every copy or move is undoable.
- **Dual Pane and Workspaces**: two folders side by side (F5 copy, F6 move to the other pane), and saved sets of tabs you reopen from the sidebar.
- **Smart Clean**: scans your Mac and groups findings into "Safe to clear" and "Your call". Nine rules:
  developer caches, stale developer data, duplicate files, used installers, Mail attachment copies,
  large files, apps you have not opened, old screen recordings, old downloads.
- **Tidy Downloads**: previews, then sorts loose files into `Images`, `Videos`, `Audio`, `Documents`, `Archives`, `Installers`, `Code` and `Other` folders. Skips hidden files, folders, aliases and half-finished downloads.
- **History and Undo**: every batch is journaled; undo the latest with Cmd+Z or any batch from the History screen, with a per-item result.
- **Uninstall Apps**: removes an app together with the caches, preferences and support files it left in `~/Library`, and Smart Clean finds leftovers of apps you already deleted. All undoable.
- **Preview pane, cut, cloud and tags**: Shift+Cmd+P live preview with folder contents, Cmd+X / Cmd+V moves, Google Drive / Dropbox / OneDrive and color tags in the sidebar.
- **Batch rename**: replace, add text, name + number, or change case for many items, with a live preview; one Cmd+Z undoes it.
- **Search**: Cmd+F filters the current folder or searches all subfolders (Spotlight on the startup disk), ignoring case and accents.
- **Space Map**: scans your home (or any folder) and shows what takes the most space, level by level; move items to the Trash from there, undoable.
- **Storage bar**: startup disk usage split into Apps, Trash, Selected, Other and Free.
- **Bilingual**: English and Vietnamese, following the system language or chosen in Settings.

## Safety promises

- Files are only ever moved to the Trash (`FileManager.trashItem`). No permanent delete, no Empty Trash.
- Every item is re-validated right before it is touched (still exists, size and modification date unchanged since the scan). Anything that changed is skipped, not moved.
- A hard deny-list (`PathGuard`) protects system folders, your home folders themselves, the Trash, iCloud containers, Apple apps and Pinax itself.
- Undo history is written to disk (`~/Library/Application Support/Pinax/journal.json`) and survives relaunch.
- Nothing leaves your Mac: no network code, no analytics, no accounts.

The full contract is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#safety-contract).

## Install

1. Download `Pinax-<version>-arm64.dmg` from [Releases](https://github.com/duchuynguyen93/pinax/releases) (check it against `SHA256SUMS.txt`).
2. Open the DMG and drag **Pinax** into **Applications**.
3. Pinax is ad-hoc signed (no paid Apple Developer ID), so Gatekeeper blocks the first launch. Do one of:
   - Open the app once, then go to **System Settings > Privacy & Security**, scroll down to the message about "Pinax" and click **Open Anyway**.
   - Or run in Terminal: `xattr -dr com.apple.quarantine /Applications/Pinax.app`

Requirements: Apple Silicon Mac, macOS 26 or later.

**Permissions.** macOS asks for access to Desktop, Documents and Downloads the first time Pinax looks there; the scan waits until you answer. **Full Disk Access** is optional: it only unlocks scanning Mail's attachment cache and measuring the Trash size in the storage bar. Because the signature is ad-hoc, macOS forgets these permissions each time the app binary changes (new version or rebuild).

## Build from source

Needs macOS 26+ and a Swift 6 toolchain (Xcode).

```sh
swift build          # debug build
swift test           # run PinaxCore tests
./build.sh           # release build -> Pinax.app (arm64, ad-hoc signed)
./build.sh dmg       # also dist/Pinax-<version>-arm64.dmg, .zip and SHA256SUMS.txt
```

The version lives in the [`VERSION`](VERSION) file.

## Roadmap

| Milestone | Scope | Status |
|---|---|---|
| M1 | Smart Clean, Tidy Downloads, History and Undo, Settings | Done (0.1.0) |
| M2 | File browser, git-aware path bar, open in Terminal/Editor, global hotkey / Services / Open With / `pinax://` entry points (macOS 27 refuses third-party default folder viewers) | Done (0.2.0) |
| M3 | Copy/move queue with undo, Finder clipboard interop, drag and drop, dual pane, workspaces | Done (0.3.0) |
| M4 | Uninstall apps with their `~/Library` files, App leftovers rule, Quick Look in lists (Empty Trash dropped on purpose) | Done (0.4.0) |
| M5 | Space Map: what takes up space, drill down, move to Trash; Analyze Size from the browser | Done (0.5.0) |
| M6 | Search: filter this folder or find in subfolders (Spotlight / fts), accent-insensitive | Done (0.6.0) |
| M7 | Batch rename (replace, add, format, case) with preview and one-step undo | Done (0.7.0) |
| M8 | Preview pane, Cmd+X cut, cloud drives and color tags in the sidebar | Done (0.8.0) |

## Documentation

- [GUIDE.md](GUIDE.md): user guide
- [CHANGELOG.md](CHANGELOG.md): release notes
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): design and safety contract
- [CONTRIBUTING.md](CONTRIBUTING.md): how to build, test and contribute
- [AGENTS.md](AGENTS.md): instructions for AI coding agents
- [docs/plans/](docs/plans/README.md): milestone plans

## License

MIT. See [LICENSE](LICENSE).

---

## Tiếng Việt

Pinax là tiện ích macOS miễn phí, mã nguồn mở, viết bằng SwiftUI thuần, giúp tìm rác chiếm dung lượng và sắp xếp thư mục Downloads. Pinax **không bao giờ xoá**: mọi thao tác chỉ là chuyển vào Thùng rác và hoàn tác được từ Lịch sử. Các bản sau sẽ phát triển thành trợ thủ cho Finder với trình duyệt file riêng.

- **Dọn dẹp thông minh**: 9 luật (cache lập trình, dữ liệu lập trình đã cũ, file trùng, bộ cài đã dùng, file đính kèm Mail, file lớn, app lâu không mở, bản ghi màn hình cũ, tải xuống đã lâu), chia nhóm "An toàn để dọn" và "Tuỳ bạn quyết".
- **Sắp xếp Downloads**: xem trước rồi xếp file lẻ vào thư mục theo loại.
- **Lịch sử và Hoàn tác**: Cmd+Z hoặc từ màn Lịch sử; lịch sử còn nguyên sau khi mở lại app.
- **An toàn**: chỉ chuyển vào Thùng rác, kiểm tra lại từng mục ngay trước khi làm, có danh sách đường dẫn cấm, không gửi gì ra ngoài máy.
- **Xem trước, cắt, cloud, tag**: khung xem trước (Shift+Cmd+P), Cmd+X / Cmd+V để chuyển, Google Drive / Dropbox / OneDrive và tag màu trên sidebar.
- **Đổi tên hàng loạt**: thay chữ, thêm chữ, tên + số thứ tự, đổi hoa thường cho nhiều mục, xem trước từng tên, một Cmd+Z là trả lại.
- **Tìm kiếm**: Cmd+F lọc thư mục đang xem hoặc tìm trong mọi thư mục con, không phân biệt hoa thường và dấu.
- **Bản đồ dung lượng**: quét Home hoặc thư mục bất kỳ, xem cái gì nặng nhất theo từng cấp, chuyển vào Thùng rác ngay tại đó (hoàn tác được).
- **Cài đặt**: tải DMG ở [Releases](https://github.com/duchuynguyen93/pinax/releases), kéo vào Applications. App ký ad-hoc nên lần đầu bị Gatekeeper chặn: vào **Cài đặt hệ thống > Quyền riêng tư & Bảo mật > Vẫn mở**, hoặc chạy `xattr -dr com.apple.quarantine /Applications/Pinax.app`. Chỉ hỗ trợ Mac Apple Silicon, macOS 26 trở lên.

Hướng dẫn chi tiết (có phần tiếng Việt) xem [GUIDE.md](GUIDE.md).
