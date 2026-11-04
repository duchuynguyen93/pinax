# Pinax User Guide

Pinax finds disk clutter and tidies your Downloads folder. It only ever moves things to the Trash, and you can undo every batch. (Tiếng Việt: see [section 10](#10-tiếng-việt).)

1. [Install](#1-install)
2. [First run and permissions](#2-first-run-and-permissions)
3. [Smart Clean](#3-smart-clean)
4. [Downloads (Tidy)](#4-downloads-tidy)
5. [History and Undo](#5-history-and-undo)
6. [Settings](#6-settings)
7. [Keyboard shortcuts](#7-keyboard-shortcuts)
8. [Troubleshooting](#8-troubleshooting)
9. [Uninstall](#9-uninstall)
10. [Tiếng Việt](#10-tiếng-việt)

---

## 1. Install

Requirements: Apple Silicon Mac, macOS 26 or later.

1. Download `Pinax-<version>-arm64.dmg` from [Releases](https://github.com/duchuynguyen93/pinax/releases). Optionally compare `shasum -a 256` with `SHA256SUMS.txt`.
2. Open the DMG and drag **Pinax** to **Applications**.
3. First launch: the app is ad-hoc signed, so Gatekeeper blocks it. Either
   - open it once, then **System Settings > Privacy & Security**, find the message about "Pinax" and click **Open Anyway**; or
   - run `xattr -dr com.apple.quarantine /Applications/Pinax.app` in Terminal.

Building from source is described in the [README](README.md#build-from-source).

## 2. First run and permissions

The first scan makes macOS ask whether Pinax may access **Desktop**, **Documents** and **Downloads** folders. Allow them, otherwise those folders cannot be scanned. The scan waits (it can look stuck) until you answer the dialog.

**Full Disk Access is optional.** Grant it in System Settings > Privacy & Security > Full Disk Access (Settings > Permissions in Pinax has a button) to unlock:

- the **Mail attachments** rule (Mail's cache is protected; without access that row shows a warning and the other rules run normally);
- the **Trash** size in the storage bar (otherwise it shows "—").

Everything else works without it.

## 3. Smart Clean

Press **Scan**. Pinax runs all rules in parallel, shows progress per rule, and you can **Cancel**. Results are split into two sections:

- **Safe to clear**: regenerable or already-used files.
- **Your call**: only you know whether you still need them.

Each rule is a row with a tri-state checkbox, total size and item count. Expand it to see items (checkbox, name, size, reason, "Show in Finder"). Very long lists show the largest 200 items; the row checkbox still covers all of them. The bottom bar shows what you selected; **Move N items to Trash** opens a confirmation, and afterwards a toast offers **Undo**.

A path appears under one rule only (the first in the order below). A selected folder covers things inside it.

| Rule | Section | What it finds | Defaults | Pre-ticked |
|---|---|---|---|---|
| Developer caches | Safe | Xcode DerivedData, CoreSimulator caches, Homebrew, npm (`~/.npm/_cacache`), pip, Yarn, CocoaPods, SwiftPM and Gradle caches | Each folder 10 MB or larger | Yes |
| Stale developer files | Your call | Xcode iOS DeviceSupport folders; `node_modules` in project folders whose parent folder was not modified for a long time | 180 days; project folders default to `~/Code`, `~/Developer`, `~/Projects` (those that exist), depth 6 | No |
| Duplicate files | Your call | Identical files in Downloads, Desktop and Documents (size, then first 64 KB, then full SHA-256). Keeps the most recently used copy (else most recently modified) | Files 1 MB or larger; hardlinks and iCloud placeholders ignored | Only when every copy is inside Downloads |
| Used installers | Safe | `.dmg`, `.pkg`, `.zip` directly in Downloads or Desktop whose name matches an installed app (e.g. `Slack-4.41.105-macOS.dmg`). Mounted DMGs are skipped | Name match after dropping versions and words like "macos", "universal", "arm64" | `.dmg`/`.pkg` yes, `.zip` no |
| Mail attachments | Safe | Files Mail saved to its Mail Downloads folder | Needs Full Disk Access | Yes |
| Large files | Your call | Files in your home folder above a size, except `~/Library`, the Trash and the contents of packages (Photos library, apps, ...) | 500 MB | No |
| Apps you haven't opened | Your call | Apps in `/Applications` and `~/Applications` last opened long ago. Apple apps and Pinax are never listed | 180 days. If macOS does not know when an app was last used, it is **never** flagged | No |
| Old screen recordings | Your call | `.mov` files named "Screen Recording..." / "Bản ghi màn hình..." in Desktop, Documents, Movies and your custom screenshot location | 30 days | No |
| Old downloads | Your call | Items (files and folders) directly in Downloads not opened or added for a long time | 90 days. Items with no known date are skipped | No |

Caveats:

- **APFS clones.** Duplicates (and copies made by Finder) can share disk blocks. Moving one may free less space than the size shown; the row says so.
- **Folders that change after the scan.** A cache folder in use (for example Xcode DerivedData while Xcode runs) changes constantly. Pinax re-checks size and modification date right before moving and skips anything that changed ("Folder changed since scan"). Rescan and try again, ideally with the app closed.
- **Selecting every copy of a duplicate.** Pinax warns and offers to deselect, so you never lose all copies.
- **Apps.** Unused apps move to the Trash like any file; their settings and leftovers are not touched (leftover cleanup is planned for M1.5).
- Nothing is ever emptied from the Trash. Use **Settings > Open Trash** and empty it yourself when you are sure.

## 4. Downloads (Tidy)

The **Downloads** screen previews how loose files in a folder (default `~/Downloads`) would be sorted. Only files directly inside that folder are considered. Untick a type to leave it alone, then press **Tidy** (or Option+Cmd+T). Folders are created only for types that have files, and a toast offers **Undo**.

Folders and what goes in them:

| Folder | Content |
|---|---|
| Installers | `.dmg`, `.pkg`, `.mpkg` |
| Archives | zip, rar, 7z, tar, gz, bz2, xz, tgz and other archive types |
| Images | Photos, screenshots, graphics |
| Videos | Movies and video |
| Audio | Music and audio |
| Documents | PDF, text, RTF, Office, iWork, CSV, Markdown, EPUB |
| Code | json, yaml, shell, xml, html, css, source code |
| Other | Everything else |

Skipped, with the reason shown in the list:

| Reason | Why |
|---|---|
| Hidden file | Names starting with a dot belong to apps or the system |
| Folder | Only loose files are moved; your folders stay as they are |
| Alias or link | Moving a link could break what points to it |
| Download in progress | `.crdownload`, `.download`, `.part`, `.partial`, `.opdownload` are unfinished |
| Modified in the last minute | The file may still be written |
| Protected location | Fails the safety check |

**Name conflicts.** Pinax never overwrites. If `report.pdf` already exists in `Documents/`, the new one becomes `report 2.pdf`, then `report 3.pdf`, and so on (also when two incoming files share a name). Folders you already have are reused and never touched; undo only removes a folder Pinax created, and only if it is empty.

You can change the folder to tidy in Settings.

## 5. History and Undo

Every batch (Smart Clean or Tidy) is recorded in **History**: date, title, number of steps, and whether it was undone. The latest 50 batches are kept and survive relaunch. Undo from the History row, from the toast, or with **Cmd+Z** (undoes the newest batch not yet undone). The result is shown per item, "Restored 3 of 4".

Items that could not be restored, or were skipped when moving, tell you why:

| Message | Meaning |
|---|---|
| No longer exists | The item is gone (for example you emptied the Trash) |
| Changed since scan | The file or folder was modified after the scan, so Pinax left it. Rescan |
| Protected location, never touched | The path is on the safety deny-list |
| Is a link, skipped | Symlinks are never moved |
| A file with this name already exists at the destination | Tidy refuses to overwrite |
| The original location already has a file | Undo will not replace the file that is there now; the item stays in the Trash |
| Folder is not empty, kept | A folder created by Tidy now has files in it, so it stays |

An undo of a batch whose items you already took out of the Trash reports them as gone; it never fails the whole batch because of one item.

## 6. Settings

- **Language**: System, English, Tiếng Việt. Applies instantly.
- **Thresholds**: large file size (MB), and days for old downloads (90), unused apps (180), screen recordings (30), stale projects (180).
- **Project folders**: where to look for old `node_modules`.
- **Tidy folder**: the folder the Downloads screen organises (default Downloads).
- **Permissions**: Full Disk Access status and a shortcut to System Settings.
- **Trash**: opens the Trash. Pinax never empties it.

## 7. Keyboard shortcuts

| Shortcut | Action |
|---|---|
| Cmd+Z | Undo the latest batch (Edit menu: "Undo Last Batch") |
| Option+Cmd+T | Tidy the selected folder (File menu: "Tidy Folder") |
| Return / Esc | Confirm / cancel in the confirmation sheet |

## 8. Troubleshooting

- **"Pinax can't be opened" / blocked by Gatekeeper.** See [Install](#1-install): Open Anyway or the `xattr` command.
- **Permissions asked again after an update or rebuild.** The signature is ad-hoc and changes with every build, so macOS treats each build as a new app. Allow again; Full Disk Access may need to be removed and re-added in System Settings.
- **Trash size shows "—".** Pinax cannot read `~/.Trash` without Full Disk Access. Grant it or ignore it; cleaning is unaffected.
- **Scan seems stuck.** A permission dialog for Desktop, Documents or Downloads may be hidden behind another window. Answer it and the scan continues.
- **Mail attachments row shows a warning.** Needs Full Disk Access.
- **An item says it changed since the scan.** It was modified between scanning and moving (caches in use change often). Rescan.
- **History looks empty after a crash or reset.** The journal is `~/Library/Application Support/Pinax/journal.json`. If it was corrupted, Pinax keeps the old copy as `journal.corrupt.json` next to it.

## 9. Uninstall

1. Quit Pinax and delete `/Applications/Pinax.app`.
2. Optionally delete its data:
   - `~/Library/Application Support/Pinax` (undo history)
   - preferences: `defaults delete com.duchuynguyen93.pinax`
3. Items Pinax moved earlier are still in your Trash until you empty it. Undo them first if you want them back.

## 10. Tiếng Việt

**Cài đặt.** Cần Mac Apple Silicon, macOS 26 trở lên. Tải `Pinax-<phiên bản>-arm64.dmg` ở [Releases](https://github.com/duchuynguyen93/pinax/releases), kéo Pinax vào Applications. Lần đầu bị Gatekeeper chặn (app ký ad-hoc): vào **Cài đặt hệ thống > Quyền riêng tư & Bảo mật > Vẫn mở**, hoặc chạy `xattr -dr com.apple.quarantine /Applications/Pinax.app`.

**Quyền.** Lần quét đầu macOS hỏi quyền vào Desktop, Documents, Downloads, hãy cho phép (quét sẽ đứng chờ tới khi bạn trả lời). Quyền **Toàn bộ ổ đĩa (Full Disk Access)** là tuỳ chọn: chỉ để quét file đính kèm của Mail và đo dung lượng Thùng rác (không có thì hiện "—").

**Dọn dẹp thông minh.** Bấm **Quét**; kết quả chia hai nhóm: *An toàn để dọn* (cache lập trình, bộ cài đã dùng, file đính kèm Mail) và *Tuỳ bạn quyết* (dữ liệu lập trình cũ, file trùng, file lớn, app lâu không mở, bản ghi màn hình cũ, tải xuống đã lâu). Ngưỡng mặc định: cache từ 10 MB; project/DeviceSupport cũ 180 ngày; file trùng từ 1 MB; file lớn 500 MB; app lâu không mở 180 ngày (nếu macOS không biết lần mở cuối thì không bao giờ gắn cờ); bản ghi màn hình 30 ngày; tải xuống 90 ngày. Mục được tick sẵn: cache lập trình, `.dmg`/`.pkg` đã cài, file Mail, và file trùng khi mọi bản đều nằm trong Downloads. Lưu ý: APFS clone có thể khiến dung lượng thu hồi thực tế ít hơn số hiển thị; thư mục đang được dùng (vd DerivedData lúc mở Xcode) có thể bị bỏ qua vì "đã thay đổi từ lúc quét", hãy quét lại. Pinax không bao giờ đổ Thùng rác.

**Sắp xếp Downloads.** Màn **Downloads** xem trước rồi xếp file lẻ cấp 1 vào `Images`, `Videos`, `Audio`, `Documents`, `Archives`, `Installers`, `Code`, `Other`. Bỏ qua file ẩn, thư mục, alias/liên kết, file đang tải dở, file vừa sửa trong 1 phút. Trùng tên thì đổi thành `tên 2.ext`, `tên 3.ext`, không bao giờ ghi đè. Phím tắt **Option+Cmd+T**.

**Lịch sử và Hoàn tác.** Mỗi lần dọn/sắp xếp là một batch, giữ 50 batch gần nhất, còn nguyên sau khi mở lại app. Hoàn tác bằng **Cmd+Z**, nút trên toast hoặc trong màn Lịch sử. Mục bị bỏ qua sẽ có lý do (không còn tồn tại, chỗ cũ đã có file, thư mục không rỗng...).

**Sự cố thường gặp.** Hỏi lại quyền sau mỗi lần build/cập nhật là bình thường (chữ ký ad-hoc đổi mỗi bản); quét "đứng" thường là đang chờ hộp thoại quyền; Thùng rác hiện "—" vì thiếu Full Disk Access.

**Gỡ cài đặt.** Xoá `/Applications/Pinax.app`, `~/Library/Application Support/Pinax`, và chạy `defaults delete com.duchuynguyen93.pinax`.
