import Foundation

/// Trạng thái "cắt" (⌘X): các đường dẫn đã cắt + changeCount của pasteboard lúc cắt.
/// Pasteboard đổi (chép thứ khác, kể cả từ app khác) → changeCount lệch → không còn là cắt.
public struct CutState: Equatable, Sendable {
    public let changeCount: Int
    public let paths: Set<String>

    public init(changeCount: Int, paths: Set<String>) {
        self.changeCount = changeCount
        self.paths = paths
    }

    public func isActive(currentChangeCount: Int) -> Bool { changeCount == currentChangeCount }

    public func isCut(_ path: String, currentChangeCount: Int) -> Bool {
        isActive(currentChangeCount: currentChangeCount) && paths.contains(path)
    }
}
