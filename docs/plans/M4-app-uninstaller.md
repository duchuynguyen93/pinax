# M4 — Gỡ app sạch + rác của app đã gỡ (v0.4.0)

> Mục tiêu: gỡ một app kèm file nó để lại trong `~/Library`, và tìm rác của các app đã gỡ từ trước. Mọi thứ vào Thùng rác, hoàn tác được.
> Thay cho mục M1.5. **Không làm Empty Trash** (README hứa Pinax không bao giờ xoá vĩnh viễn). Quick Look trong danh sách Smart Clean làm luôn ở đây.

## 1. Phạm vi

**Trong M4:**
- Core `AppFootprint`: từ một app (bundle id, tên, team id) tìm các mục liên quan trong `~/Library`.
- Màn **Uninstall Apps** (sidebar nhóm Pinax): danh sách app đã cài, chọn một app → app + các file liên quan (có tick), tổng dung lượng, "Move to Trash". Thả `.app` vào màn này để chọn nhanh.
- Rule Smart Clean mới **App leftovers** (nhóm "Your call", không tick sẵn): mục trong `~/Library` mang bundle id của app không còn cài.
- Space = Quick Look trong danh sách Smart Clean / Uninstall.

**Ngoài M4:** Empty Trash; `~/Library/Containers` trong rule leftovers (đọc vào là macOS hỏi quyền "dữ liệu của app khác"); file hệ thống `/Library/*` (cần quyền admin); kernel/system extension; gỡ app của Mac App Store đang do root sở hữu (báo lỗi, gợi ý Finder).

## 2. Vị trí tìm (trong `~/Library`, không đệ quy)

| Thư mục | Khớp theo bundle id `<id>` | Ghi chú |
|---|---|---|
| `Application Support/` | `<id>` | |
| `Caches/` | `<id>` | |
| `Preferences/` | `<id>.plist` | |
| `Preferences/ByHost/` | `<id>.<UUID>.plist` | |
| `Saved Application State/` | `<id>.savedState` | |
| `HTTPStorages/` | `<id>`, `<id>.binarycookies` | |
| `WebKit/` | `<id>` | |
| `Logs/` | `<id>` | |
| `Cookies/` | `<id>.binarycookies` | |
| `LaunchAgents/` | `<id>.plist`, `<id>.*.plist` | |
| `Containers/` | `<id>` | **chỉ trong Uninstall** (app đang gỡ), không trong rule |
| `Group Containers/` | `<teamID>.*` | chỉ trong Uninstall, **không tick sẵn**; ghi "dùng chung với app cùng nhà phát triển" nếu còn app khác cùng team |
| `Application Support/`, `Caches/`, `Logs/` | `<tên app>` (khớp tên, không phân biệt hoa/thường) | chỉ trong Uninstall, **không tick sẵn**, lý do "khớp theo tên" |

"Helper": mục mang id dạng `<id>.<gì đó>` (vd `com.foo.App.helper`) cũng thuộc app `<id>`.

## 3. Rule "App leftovers" — điều kiện để gắn cờ một mục mang id `X`

Tất cả phải đúng (bảo thủ, thà sót còn hơn nhầm):
1. Tên mục có dạng reverse-DNS hợp lệ (≥ 3 thành phần, chỉ chữ/số/`-`/`_`/`.`), sau khi bỏ đuôi `.plist`/`.savedState`/`.binarycookies`/`.<UUID>.plist`.
2. Không phải `com.apple.*`, không phải bundle id của Pinax.
3. Không có app nào đang cài có bundle id `== X`, là tiền tố của `X` (`X` là helper của nó), hoặc nhận `X` làm tiền tố. "Đang cài" = quét `applicationRoots` (độ sâu 2) **và** hỏi LaunchServices (`NSWorkspace.urlsForApplications(withBundleIdentifier:)`) — nguồn thứ hai tiêm được để test.
4. Không sửa trong `leftoverDays` ngày (mặc định 30) — app/daemon vẫn đang ghi thì không phải rác.
5. `LaunchAgents/*.plist`: chỉ gắn cờ khi `Program` / `ProgramArguments[0]` trỏ tới file **không còn tồn tại**.
6. Gom theo `X`: mỗi mục một candidate, lý do `.leftover(bundleID: X)`, không tick sẵn.

## 4. Gỡ app (Uninstall)

- Từ chối: app `com.apple.*`, Pinax, app trong `/System`. App đang chạy → hộp thoại "Quit <App> first" với nút Quit (`NSRunningApplication.terminate()`), chờ tối đa 5 s, vẫn chạy → dừng.
- Danh sách mặc định tick: app bundle + mục khớp bundle id (gồm Containers của chính nó). Không tick: Group Containers, khớp theo tên.
- Thực thi bằng `Executor.perform(candidates:)` (fingerprint đọc lúc bấm) → một batch "Uninstall <App>" trong History, ⌘Z trả lại tất cả.
- App root-owned không chuyển được → outcome lỗi, thông báo "Pinax can't move this app (owned by the system). Drag it to the Trash in Finder." Các mục khác vẫn làm.
- Kích thước tính nền (`SizeCalculator`), danh sách app sắp theo tên, có ô tìm.

## 5. An toàn

- Không đổi PathGuard. Mọi thao tác qua `Executor` + `Trasher`. Lệnh grep an toàn không đổi.
- Không đọc vào `~/Library/Containers/*` khi quét rule (chỉ khi người dùng chủ động gỡ một app, và chỉ thư mục của chính app đó).
- Team id lấy bằng `SecStaticCodeCreateWithPath` + `SecCodeCopySigningInformation` (`kSecCodeInfoTeamIdentifier`); không có → bỏ qua Group Containers.

## 6. Chia việc

| Bước | Việc |
|---|---|
| A | Core: `AppFootprint` (tìm mục theo §2), `InstalledBundleIndex` (roots + LaunchServices tiêm được), `TeamID`, `LeftoversRule` (§3), `ReasonKind.leftover`, `CleanSettings.leftoverDays`; test với home giả |
| B | App: màn Uninstall Apps + quit-app flow + thả `.app`; rule mới trong Smart Clean (chữ song ngữ, Settings ngưỡng ngày); Space = Quick Look trong danh sách Smart Clean/Uninstall |
| C | Opus review, QA bằng ảnh chụp (app giả trong thư mục tạm của home với file giả trong `~/Library` mang id `dev.pinax.qa.*`, dọn sau), docs, 0.4.0 |

## 7. Cổng hoàn thành

1. `swift test` xanh; test cho từng dòng §2 và từng điều kiện §3 (kể cả helper prefix, LaunchAgent còn/mất binary, mục mới sửa, com.apple).
2. `PINAX_SMOKE=1 swift test` chạy rule leftovers trên home thật **chỉ đọc**, in số lượng + 10 mục đầu để Opus soát có nhầm app đang cài không.
3. Ảnh chụp: màn Uninstall với app QA giả; Smart Clean có nhóm App leftovers.
4. Release như các bản trước.
