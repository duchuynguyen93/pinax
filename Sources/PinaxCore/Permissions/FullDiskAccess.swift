import Foundation

/// Kiểm tra quyền Full Disk Access (§3.7).
public enum FullDiskAccess {
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// Đọc được một trong hai vị trí được TCC bảo vệ → đã cấp quyền.
    public static var isGranted: Bool {
        let tcc = "/Library/Application Support/com.apple.TCC/TCC.db"
        let fd = open(tcc, O_RDONLY)
        if fd >= 0 { close(fd); return true }
        let stocks = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Containers/com.apple.stocks")
        return (try? FileManager.default.contentsOfDirectory(atPath: stocks)) != nil
    }
}
