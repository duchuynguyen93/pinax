import AppKit
import PinaxCore

extension BrowserModel {
    /// Lệnh ở ô đường dẫn (`code .`, `>term`). nil = không phải lệnh; true = đã chạy; false = là lệnh nhưng không chạy được (đã toast).
    /// Chỉ mở thư mục bằng app qua NSWorkspace, không bao giờ chạy shell.
    func runPathCommand(_ text: String) -> Bool? {
        guard let cmd = PathCommand.parse(text) else { return nil }

        let target: URL
        if let arg = cmd.argument, arg != "." {
            var p = (arg as NSString).expandingTildeInPath
            if !p.hasPrefix("/") { p = folder.appendingPathComponent(p).path }
            target = URL(fileURLWithPath: p).standardizedFileURL
            guard FileManager.default.fileExists(atPath: target.path) else {
                toast.show(L("No such path", "Không có đường dẫn này"))
                return false
            }
        } else {
            target = folder
        }

        switch cmd.target {
        case .apps(let ids):
            guard let appURL = ids.lazy.compactMap({ ExternalApps.resolve($0) }).first else {
                toast.show(L("\(cmd.name) is not installed", "Chưa cài \(cmd.name)"))
                return false
            }
            NSWorkspace.shared.open([target], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        case .terminal:
            guard let term = ExternalApps.terminal else {
                toast.show(L("No terminal app found", "Không tìm thấy app terminal"))
                return false
            }
            ExternalApps.open(target, with: term)
        case .finder:
            NSWorkspace.shared.activateFileViewerSelecting([target])
        }
        return true
    }
}
