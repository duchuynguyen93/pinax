import Foundation

/// Một nút trong cây dung lượng. Chỉ đọc khi đang quét; chỉ sửa trên main sau khi quét xong.
public final class SizeNode: @unchecked Sendable {
    public enum Kind: Sendable { case directory, package, file, others }

    /// Tên thành phần cuối; node gốc = đường dẫn đầy đủ.
    public internal(set) var name: String
    public let kind: Kind
    public internal(set) var size: Int64
    /// Số file (đệ quy); `.others` = số file được gom.
    public internal(set) var fileCount: Int
    /// Sắp theo size giảm dần sau khi quét xong.
    public internal(set) var children: [SizeNode] = []
    public internal(set) var isUnreadable = false
    public internal(set) var skipped = false
    public internal(set) weak var parent: SizeNode?

    init(name: String, kind: Kind, size: Int64 = 0, fileCount: Int = 0) {
        self.name = name
        self.kind = kind
        self.size = size
        self.fileCount = fileCount
    }

    /// Dựng từ chuỗi parent (others → url của thư mục cha).
    public var url: URL {
        guard let parent else { return URL(fileURLWithPath: name) }
        if kind == .others { return parent.url }
        return parent.url.appendingPathComponent(name, isDirectory: kind == .directory || kind == .package)
    }

    public var isTrashable: Bool { kind != .others && parent != nil }

    /// Gỡ node khỏi cây, trừ size/fileCount ở mọi tổ tiên. Trả false nếu là gốc.
    @discardableResult
    public func removeFromParent() -> Bool {
        guard let p = parent else { return false }
        p.children.removeAll { $0 === self }
        adjustAncestors(size: -size, files: -fileCount)
        parent = nil
        return true
    }

    /// Thay node `skipped` bằng kết quả quét mới (cùng url), cộng chênh lệch lên tổ tiên.
    public func replace(with scanned: SizeNode) {
        guard let p = parent else { return }
        guard let i = p.children.firstIndex(where: { $0 === self }) else { return }
        scanned.name = name
        scanned.parent = p
        p.children[i] = scanned
        parent = nil
        p.adjust(size: scanned.size - size, files: scanned.fileCount - fileCount)
        p.children.sort(by: SizeNode.bySizeDesc)
    }

    private func adjustAncestors(size: Int64, files: Int) {
        parent?.adjust(size: size, files: files)
    }

    private func adjust(size: Int64, files: Int) {
        var n: SizeNode? = self
        while let cur = n {
            cur.size += size
            cur.fileCount += files
            n = cur.parent
        }
    }

    static func bySizeDesc(_ a: SizeNode, _ b: SizeNode) -> Bool {
        a.size != b.size ? a.size > b.size : a.name < b.name
    }
}
