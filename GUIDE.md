# Pinax User Guide

Pinax is a file browser that also finds disk clutter and tidies your Downloads folder. It only ever moves things to the Trash, and you can undo every batch. (Tiếng Việt: see [section 10](#10-tiếng-việt).)

1. [Install](#1-install)
2. [First run and permissions](#2-first-run-and-permissions)
3. [Smart Clean](#3-smart-clean)
4. [Downloads (Tidy)](#4-downloads-tidy)
5. [History and Undo](#5-history-and-undo)
   - [Browsing](#browsing), [File operations](#file-operations), [Copy and move](#copy-and-move), [Dual Pane and Workspaces](#dual-pane-and-workspaces), [Opening folders in Pinax](#opening-folders-in-pinax)
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
| App leftovers | Your call | Files in `~/Library` named after the bundle id of an app that is no longer installed (see below) | 30 days untouched | No |
| Old downloads | Your call | Items (files and folders) directly in Downloads not opened or added for a long time | 90 days. Items with no known date are skipped | No |

Caveats:

- **APFS clones.** Duplicates (and copies made by Finder) can share disk blocks. Moving one may free less space than the size shown; the row says so.
- **Folders that change after the scan.** A cache folder in use (for example Xcode DerivedData while Xcode runs) changes constantly. Pinax re-checks size and modification date right before moving and skips anything that changed ("Folder changed since scan"). Rescan and try again, ideally with the app closed.
- **Selecting every copy of a duplicate.** Pinax warns and offers to deselect, so you never lose all copies.
- **Apps.** Unused apps move to the Trash like any file; their settings and leftovers are not touched (leftover cleanup is planned for M1.5).
- Nothing is ever emptied from the Trash. Use **Settings > Open Trash** and empty it yourself when you are sure.

**App leftovers** is cautious on purpose. It skips: anything of an app Pinax can find (in /Applications, ~/Applications, Spotlight or LaunchServices), helpers of installed apps, other apps' files from the same developer or carrying the name of an installed app, command-line tools found in `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.cargo/bin` and similar, Apple and system components, folders whose contents changed in the last 30 days, and LaunchAgents whose program still exists. It never looks inside `~/Library/Containers`. Check each item before ticking it: an Application Support folder can hold settings or keys of a tool you still use elsewhere.

### Uninstall Apps

Sidebar > Pinax > **Uninstall Apps** lists the apps in /Applications and ~/Applications (Apple apps and Pinax are not listed). Select one, or drop a `.app` onto the screen, to see the app plus what it keeps in `~/Library`. Items found by its bundle id are ticked; items that only match its name, and shared developer group containers, are shown but not ticked. Space previews the focused item. **Move to Trash** asks running apps to quit first, then moves everything ticked to the Trash as one History entry: Cmd+Z puts it all back. An app owned by the system (some App Store apps) cannot be moved by Pinax; drag it to the Trash in Finder, the other items still go.

### Space Map

Sidebar > Pinax > **Space Map** shows what takes up space. Press **Scan Home** or **Choose Folder…**, or right-click a folder in the browser and pick **Analyze Size**. Top-level folders appear as soon as each one is counted; a full home folder with a couple of million files takes about a minute or more, about as long as `du`. Then:

- The bar and the list show the biggest items of the current folder. Double-click or Return opens a folder; Cmd+Up and the breadcrumb go back up.
- Space previews, Cmd+Delete moves the selection to the Trash (one History entry, Cmd+Z undoes), and the right-click menu has **Reveal in Browser** and **Analyze Here**.
- Sizes are real space on disk. Symlinks are not followed, other disks are not counted, hard links count once, apps and other packages are a single item, and files under 1 MB are grouped as "smaller files". Two APFS clones of the same file are counted twice (macOS has no cheap way to tell).
- `Library/Containers` and `Library/Group Containers` are not scanned automatically because macOS would ask for permission to read other apps' data. Press **Scan** on that row if you want them. Folders that need Full Disk Access are shown as unreadable.
- After an undo the results may be out of date; press **Rescan**.

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

## Browsing

Pinax opens on a browser window. The sidebar has your Favorites (drag to reorder, right-click to remove; Ctrl+Cmd+T adds the current folder), Locations (disks, with an Eject button for external ones) and the Pinax tools (Smart Clean, Tidy Downloads, History).

- **Views.** Cmd+1 list (click a column header to sort), Cmd+2 icons with thumbnails; Cmd+- / Cmd+= change the icon size. Folder sizes fill in in the background.
- **Moving around.** Double-click or Cmd+Down opens, Cmd+Up goes to the enclosing folder, Cmd+[ / Cmd+] go back and forward. Click any part of the path bar to jump there.
- **Go to Path** (Cmd+L): type a path (`~` works), Tab completes (press Tab again to cycle through matches, Shift+Tab backwards), Return goes, Esc cancels. A path to a file opens its folder with the file selected.
- **Quick Look**: Space on the selection.
- **Tabs**: Cmd+T for a new tab in the same folder.
- **Hidden files**: Shift+Cmd+. toggles them.
- The folder refreshes on its own when files change.

## File operations

Everything below is journaled, shows up in History and is undone with Cmd+Z (Edit > Undo). Nothing is ever deleted permanently.

- **New Folder** (Shift+Cmd+N): creates `untitled folder` (or `untitled folder 2`...) in the current folder, selects it and starts renaming.
- **Rename** (Return on one selected item, or right-click > Rename): edit in place in the list, or under the icon in icon view. The name without its extension is selected. Return confirms, Esc cancels. A name that already exists is refused and the old name stays.
- **Move to Trash** (Cmd+Delete): no confirmation, because it is undoable. A toast offers Undo and lists anything skipped.
- **Copy Path** (Option+Cmd+C): plain POSIX paths, one per line (the current folder when nothing is selected).
- Pinax does not modify protected locations (system folders, volume roots, your home folders themselves, the Trash...): the commands are greyed out or say "Pinax doesn't modify this location".

**Context menu** (right-click an item or empty space): Open, Open With (default app first, then others, then Other...), Quick Look, Rename, New Folder, Move to Trash, Copy Path, Show in Finder, Open in Terminal, Open in Editor.

**Git in the path bar.** Inside a git repository the right side of the path bar shows the branch (or the short commit when detached), commits ahead/behind, and the number of changed files; hover for staged / modified / untracked / conflicted counts. It is read-only, refreshes when the folder changes or the window becomes active, and is hidden outside repositories or when Xcode Command Line Tools are not installed.

## Copy and move

- **Clipboard.** Cmd+C copies the selected files; paste them in Pinax with Cmd+V, or in Finder. Files copied in Finder paste into Pinax the same way. Option+Cmd+V moves them into the current folder instead (Finder's "Move Item Here"). Cmd+D duplicates the selection as `name copy.ext`.
- **Drag and drop.** Drop files onto the list, the icon grid, a folder row or a Favorite. Within the same disk the files are moved, to another disk they are copied; hold Option to copy or Command to move. Dragging from Pinax into Finder lets Finder do the work (that one is not in Pinax's History).
- **Progress.** A strip above the status bar shows the job, bytes copied and the current item; the ⓧ button stops it. Items finished before you stop stay and are undoable; the unfinished one is removed by moving it to the Trash. Jobs run one after another.
- **Name conflicts.** Pinax asks once per job: **Keep Both** (`name 2.ext`), **Replace** (the old item is moved to the Trash first, so Cmd+Z brings it back), **Skip**, or **Cancel**.
- **Undo.** Cmd+Z (or History) undoes a whole job: copies are moved to the Trash, moved files go back, replaced items come back from the Trash. Moving to another disk copies first and only then moves the original to the Trash.
- Pinax never copies a folder into itself, never writes into protected locations, and never overwrites a file in place.

## Dual Pane and Workspaces

- **Dual Pane** (View > Dual Pane, Cmd+\\): two folders side by side, each with its own back/forward history and selection. The active pane has a blue line under its path bar; the sidebar, toolbar and menus act on it. Tab switches panes. **F5** copies and **F6** moves the selection to the other pane (also in the right-click menu). Each window remembers its panes.
- **Workspaces.** File > Save Window as Workspace (Ctrl+Cmd+S) saves all tabs of the front window, including both panes and the view mode. Saved workspaces appear in the sidebar: click one to open it in a new window with all its tabs; right-click to Rename, Update from Current Window or Delete (deleting removes only the saved layout). `pinax://workspace?name=Work` opens one from Raycast, Alfred or Shortcuts. Stored in `~/Library/Application Support/Pinax/workspaces.json`.

## Opening folders in Pinax

macOS 27 does not let a third-party app replace Finder as the default folder viewer (details: [plan, section 0](docs/plans/M2-file-browser.md)). Pinax offers these entry points instead:

- **Global shortcut.** Option+Cmd+P brings Pinax to the front, or opens a window if none is open. Change, record or turn it off in Settings > Global shortcut. It needs no Accessibility permission; if the combination is taken by another app Settings shows a warning.
- **Services.** In Finder, right-click a folder (or file) > Services (or Quick Actions) > **Open in Pinax**. If the item is missing, enable it in System Settings > Keyboard > Keyboard Shortcuts > Services > Files and Folders > "Open in Pinax". A new service may need a re-login or `/System/Library/CoreServices/pbs -update` before it shows up.
- **Open With.** Right-click a folder > Open With > Pinax (it is listed as an alternate, never the default).
- **Terminal.** `open -a Pinax .` opens the current directory; add `alias pinax='open -a Pinax'` to your shell profile and run `pinax ~/Downloads`.
- **URL.** `pinax://open?path=%2FUsers%2Fme%2FDownloads` (percent-encode the path) for Raycast, Alfred or Shortcuts. Each URL, like each Services or Open With request, opens a new window (as Finder does). A file opens its folder with the file selected; a missing path opens Home with a notice.
- **Open in Terminal / Editor.** Pick the apps in Settings; then File > Open in Terminal (Option+Shift+Cmd+T) or Open in Editor (Option+Shift+Cmd+E) for the folder in the front window.

Tiếng Việt: Pinax không thể thành trình duyệt thư mục mặc định trên macOS 27, nên dùng phím tắt toàn cục (mặc định Option+Cmd+P), Services "Open in Pinax", Mở bằng (Open With), `open -a Pinax .` hoặc `pinax://open?path=…`.

## 6. Settings

- **Language**: System, English, Tiếng Việt. Applies instantly.
- **Thresholds**: large file size (MB), and days for old downloads (90), unused apps (180), screen recordings (30), stale projects (180).
- **Project folders**: where to look for old `node_modules`.
- **Tidy folder**: the folder the Downloads screen organises (default Downloads).
- **Global shortcut**, **Open in Terminal / Editor**: see [Opening folders in Pinax](#opening-folders-in-pinax).
- **Permissions**: Full Disk Access status and a shortcut to System Settings.
- **Trash**: opens the Trash. Pinax never empties it.

## 7. Keyboard shortcuts

| Shortcut | Action |
|---|---|
| Cmd+Z | Undo the latest batch (while typing a name or path it undoes the typing instead) |
| Cmd+1 / Cmd+2 | List / icon view |
| Cmd+L | Go to Path (Tab completes) |
| Cmd+[ / Cmd+] / Cmd+Up | Back / Forward / Enclosing Folder |
| Space | Quick Look |
| Cmd+T | New tab |
| Option+Cmd+P | Bring Pinax to the front from any app (changeable in Settings) |
| Shift+Cmd+N | New Folder (then rename in place) |
| Return | Rename the selected item (Esc cancels) |
| Cmd+Delete | Move the selection to the Trash (also in Space Map) |
| Option+Cmd+C | Copy path(s) |
| Cmd+C / Cmd+V | Copy / paste files (works with Finder) |
| Option+Cmd+V | Move the copied files here |
| Cmd+D | Duplicate |
| Cmd+\\ | Dual Pane on/off |
| Tab | Switch pane (dual pane) |
| F5 / F6 | Copy / move to the other pane |
| Ctrl+Cmd+S | Save window as workspace |
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

**Trình duyệt file.** Cửa sổ chính là trình duyệt: Cmd+1 dạng danh sách, Cmd+2 dạng lưới; Cmd+L gõ đường dẫn (Tab để hoàn thành); Space để Quick Look; Cmd+T mở tab. Shift+Cmd+N tạo thư mục, Return đổi tên, Cmd+Delete chuyển vào Thùng rác; tất cả đều hoàn tác được bằng Cmd+Z. Trong repo git, thanh đường dẫn hiện nhánh và số thay đổi.

**Chép và chuyển.** Cmd+C / Cmd+V để chép file (dán qua lại với Finder được), Option+Cmd+V để chuyển tới đây, Cmd+D nhân bản; kéo thả vào danh sách, thư mục hoặc Favorites. Trùng tên thì chọn Giữ cả hai / Thay thế (mục cũ vào Thùng rác) / Bỏ qua. Mọi lần chép, chuyển đều hoàn tác được bằng Cmd+Z.

**Hai khung và Workspace.** Cmd+\\ bật hai khung; Tab đổi khung; F5 chép, F6 chuyển sang khung kia. File > Save Window as Workspace (Ctrl+Cmd+S) lưu các tab của cửa sổ, mở lại từ sidebar hoặc `pinax://workspace?name=…`.

**Gỡ ứng dụng.** Sidebar > Pinax > Gỡ ứng dụng: chọn app (hoặc thả file .app vào) để thấy app cùng các file nó để lại trong `~/Library`; mục khớp bundle id được tick, mục chỉ khớp theo tên thì không. App đang chạy sẽ được hỏi thoát trước. Tất cả vào Thùng rác, Cmd+Z trả lại. **Bản đồ dung lượng.** Sidebar > Pinax > Bản đồ dung lượng (hoặc chuột phải một thư mục > Phân tích dung lượng): quét Home hay thư mục bất kỳ, xem cái gì nặng nhất theo từng cấp, nhấp đúp để vào sâu, Cmd+Up để lên. Cmd+Delete đưa vào Thùng rác, Cmd+Z trả lại. Không tự quét `Library/Containers` (macOS sẽ hỏi quyền), muốn thì bấm Scan ở dòng đó.

Smart Clean có thêm mục *Rác của app đã gỡ* (không tick sẵn, rất thận trọng: bỏ qua app còn cài, công cụ dòng lệnh, thành phần hệ thống, thư mục mới sửa trong 30 ngày).

**Lịch sử và Hoàn tác.** Mỗi lần dọn/sắp xếp là một batch, giữ 50 batch gần nhất, còn nguyên sau khi mở lại app. Hoàn tác bằng **Cmd+Z**, nút trên toast hoặc trong màn Lịch sử. Mục bị bỏ qua sẽ có lý do (không còn tồn tại, chỗ cũ đã có file, thư mục không rỗng...).

**Sự cố thường gặp.** Hỏi lại quyền sau mỗi lần build/cập nhật là bình thường (chữ ký ad-hoc đổi mỗi bản); quét "đứng" thường là đang chờ hộp thoại quyền; Thùng rác hiện "—" vì thiếu Full Disk Access.

**Gỡ cài đặt.** Xoá `/Applications/Pinax.app`, `~/Library/Application Support/Pinax`, và chạy `defaults delete com.duchuynguyen93.pinax`.
