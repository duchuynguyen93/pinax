import Foundation
import Observation
import PinaxCore

/// Trạng thái git của thư mục đang xem, cho path bar. Chỉ đọc, chạy nền, debounce 500 ms.
@MainActor @Observable
final class GitStatusModel {
    private(set) var summary: GitSummary?

    @ObservationIgnored private var task: Task<Void, Never>?
    /// Gốc repo của lần đọc gần nhất; đi trong cùng repo thì không cần chạy lại git.
    @ObservationIgnored private var rootPath: String?
    @ObservationIgnored private let reader = GitStatusReader()
    private static let debounce: Duration = .milliseconds(500)

    /// Sang thư mục mới: trong cùng repo thì giữ kết quả; ngoài repo cũ thì huỷ việc đang chờ, ẩn và đọc lại.
    func folderChanged(_ folder: URL) {
        if let root = rootPath, Self.isInside(folder.path, root: root) { return }
        task?.cancel()
        summary = nil
        rootPath = nil
        schedule(folder)
    }

    /// Watcher báo thư mục đổi, hoặc cửa sổ thành key.
    func refresh(_ folder: URL) {
        task?.cancel()
        schedule(folder)
    }

    private func schedule(_ folder: URL) {
        let reader = reader
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            // Tìm gốc repo rồi mới chạy git: thư mục không phải repo thì không tốn process nào.
            let result = await Task.detached(priority: .utility) { () -> (String, GitSummary)? in
                guard let root = GitStatusReader.repoRoot(of: folder), let s = reader.summary(for: folder) else { return nil }
                return (root.path, s)
            }.value
            guard let self, !Task.isCancelled else { return }
            rootPath = result?.0
            summary = result?.1
        }
    }

    private static func isInside(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
