import Foundation
import PinaxCore

// Văn bản song ngữ dùng chung cho các view / view model.

func fmtBytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

func abbreviate(_ url: URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }

func itemsText(_ n: Int) -> String { n == 1 ? L("1 item", "1 mục") : L("\(n) items", "\(n) mục") }

func ruleTitle(_ id: String) -> String {
    switch id {
    case "devCaches": L("Developer caches", "Cache công cụ lập trình")
    case "devStale": L("Stale developer files", "Dữ liệu lập trình đã cũ")
    case "duplicates": L("Duplicate files", "File trùng lặp")
    case "installers": L("Used installers", "Bộ cài đã dùng xong")
    case "mailDownloads": L("Mail attachments", "File đính kèm của Mail")
    case "largeFiles": L("Large files", "File dung lượng lớn")
    case "unusedApps": L("Apps you haven't opened", "App lâu không mở")
    case "screenRecordings": L("Old screen recordings", "Bản ghi màn hình cũ")
    case "oldDownloads": L("Old downloads", "Tải xuống đã lâu")
    default: id
    }
}

func ruleBlurb(_ id: String) -> String {
    switch id {
    case "devCaches": L("Xcode, Homebrew, npm and other caches that rebuild themselves.",
                        "Cache của Xcode, Homebrew, npm… tự tạo lại khi cần.")
    case "devStale": L("Old iOS DeviceSupport and node_modules in projects you haven't touched lately.",
                       "iOS DeviceSupport cũ và node_modules của project lâu không đụng tới.")
    case "duplicates": L("Identical files in Downloads, Desktop and Documents. The most recently used copy is kept.",
                         "File giống hệt nhau trong Downloads, Desktop, Documents. Bản dùng gần nhất được giữ lại.")
    case "installers": L("Disk images and packages of apps that are already installed.",
                         "File .dmg/.pkg/.zip của app đã được cài.")
    case "mailDownloads": L("Files Mail saved when you opened attachments.",
                            "File Mail lưu khi bạn mở đính kèm.")
    case "largeFiles": L("Files above the size set in Settings.", "File lớn hơn ngưỡng đặt trong Cài đặt.")
    case "unusedApps": L("Apps not opened for a long time.", "App đã lâu không mở.")
    case "screenRecordings": L("Screen recordings older than the limit set in Settings.",
                               "Bản ghi màn hình cũ hơn số ngày đặt trong Cài đặt.")
    case "oldDownloads": L("Items in Downloads you haven't used for a long time.",
                           "Mục trong Downloads lâu không dùng tới.")
    default: ""
    }
}

func reasonText(_ c: Candidate) -> String {
    switch c.reasonKind {
    case .installedApp(let name): L("Already installed: \(name)", "Đã cài \(name)")
    case .duplicateOf(let keeper): L("Duplicate of \(abbreviate(keeper))", "Trùng với \(abbreviate(keeper))")
    case .lastUsed(let d):
        L("Last opened \(d.formatted(date: .abbreviated, time: .omitted))",
          "Mở lần cuối \(d.formatted(date: .abbreviated, time: .omitted))")
    case .olderThan(let days): L("Older than \(days) days", "Cũ hơn \(days) ngày")
    case .devCache(let name): L("Cache: \(name)", "Cache: \(name)")
    case .staleProject(let name): L("Project \(name) untouched for a long time", "Project \(name) lâu không đụng tới")
    case .large: L("Large file", "File lớn")
    case .mailAttachment: L("Mail attachment", "File đính kèm Mail")
    case .screenRecording: L("Old screen recording", "Bản ghi màn hình cũ")
    case .other: c.reason
    }
}

func skipText(_ r: SkipReason, isFolder: Bool = false) -> String {
    switch r {
    case .missing: L("No longer exists", "Không còn tồn tại")
    case .changedSinceScan:
        isFolder ? L("Folder changed since scan (e.g. a cache in use). Rescan to try again.",
                     "Thư mục đã thay đổi từ lúc quét (vd. cache đang được dùng). Hãy quét lại để thử lần nữa.")
                 : L("Changed since scan. Rescan to try again.", "Đã thay đổi từ lúc quét. Hãy quét lại để thử lần nữa.")
    case .protectedPath: L("Protected location, never touched", "Vị trí được bảo vệ, không bao giờ động tới")
    case .symlink: L("Is a link, skipped", "Là liên kết (symlink), đã bỏ qua")
    case .destinationExists: L("A file with this name already exists at the destination", "Đã có file trùng tên ở nơi đến")
    case .originalOccupied: L("The original location already has a file", "Chỗ cũ đã có file khác")
    case .directoryNotEmpty: L("Folder is not empty, kept", "Thư mục không rỗng, đã giữ lại")
    }
}

func tidySkipText(_ r: TidySkipReason) -> String {
    switch r {
    case .hidden: L("Hidden file", "File ẩn")
    case .directory: L("Folder", "Thư mục")
    case .symlinkOrAlias: L("Alias or link", "Alias hoặc liên kết")
    case .inProgressDownload: L("Download in progress", "Đang tải dở")
    case .recentlyModified: L("Modified in the last minute", "Vừa sửa trong 1 phút")
    case .notAllowed: L("Protected location", "Vị trí được bảo vệ")
    }
}

func kindName(_ k: FileKind) -> String {
    switch k {
    case .installers: L("Installers", "Bộ cài đặt")
    case .archives: L("Archives", "File nén")
    case .images: L("Images", "Ảnh")
    case .videos: L("Videos", "Video")
    case .audio: L("Audio", "Âm thanh")
    case .documents: L("Documents", "Tài liệu")
    case .code: L("Code", "Mã nguồn")
    case .other: L("Other", "Khác")
    }
}

func kindSymbol(_ k: FileKind) -> String {
    switch k {
    case .installers: "shippingbox"
    case .archives: "doc.zipper"
    case .images: "photo"
    case .videos: "film"
    case .audio: "music.note"
    case .documents: "doc.text"
    case .code: "chevron.left.forwardslash.chevron.right"
    case .other: "doc"
    }
}

/// Một mục bị bỏ qua / lỗi, đã localize sẵn để toast và History hiển thị.
struct Problem: Identifiable {
    let id = UUID()
    let name: String
    let detail: String

    /// nil nếu outcome thành công.
    static func from(_ o: ItemOutcome) -> Problem? {
        let isFolder = (try? o.url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        switch o.status {
        case .done: return nil
        case .skipped(let r): return Problem(name: abbreviate(o.url), detail: skipText(r, isFolder: isFolder))
        case .failed(let msg): return Problem(name: abbreviate(o.url), detail: L("Failed: \(msg)", "Lỗi: \(msg)"))
        }
    }
}

// MARK: - Trình duyệt

func selectedText(_ n: Int) -> String { L("\(n) selected", "\(n) đã chọn") }
func availableText(_ size: String) -> String { L("\(size) available", "\(size) trống") }

// MARK: - Thao tác file

func protectedLocationText() -> String { L("Pinax doesn't modify this location", "Pinax không thay đổi vị trí này") }

func fileNameErrorText(_ e: FileNameError) -> String {
    switch e {
    case .empty: L("The name can't be empty.", "Tên không được để trống.")
    case .containsSeparator: L("Names can't contain “/” or “:”.", "Tên không được chứa “/” hay “:”.")
    case .reserved: L("“.” and “..” aren't valid names.", "“.” và “..” không phải tên hợp lệ.")
    case .tooLong: L("That name is too long.", "Tên quá dài.")
    case .unchanged: ""
    }
}

/// Lý do một thao tác một-mục không thành công, cho hộp thoại.
func operationFailureText(_ status: ItemStatus, name: String) -> String {
    switch status {
    case .done: ""
    case .skipped(.protectedPath): protectedLocationText()
    case .skipped(.destinationExists):
        L("An item named “\(name)” already exists in this folder.", "Đã có mục tên “\(name)” trong thư mục này.")
    case .skipped(let r): skipText(r)
    case .failed(let msg): msg
    }
}

func movedToTrashText(_ n: Int) -> String { L("Moved \(itemsText(n)) to the Trash", "Đã chuyển \(itemsText(n)) vào Thùng rác") }

func gitChangeText(_ kind: GitChangeKind, _ n: Int) -> String {
    switch kind {
    case .conflicted: L("\(n) conflicted", "\(n) xung đột")
    case .staged: L("\(n) staged", "\(n) đã stage")
    case .modified: L("\(n) modified", "\(n) đã sửa")
    case .untracked: L("\(n) untracked", "\(n) chưa theo dõi")
    }
}

func gitChangesLabel(_ n: Int) -> String { n == 1 ? L("1 change", "1 thay đổi") : L("\(n) changes", "\(n) thay đổi") }
