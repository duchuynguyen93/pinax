import Foundation

/// Một tab đã lưu: thư mục pane trái, pane phải (nil = một pane), kiểu xem, pane đang active.
public struct TabState: Codable, Equatable, Sendable {
    public var left: String
    public var right: String?
    public var viewMode: String
    public var activeRight: Bool

    public init(left: String, right: String? = nil, viewMode: String, activeRight: Bool = false) {
        self.left = left
        self.right = right
        self.viewMode = viewMode
        self.activeRight = activeRight
    }
}

public struct Workspace: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var tabs: [TabState]

    public init(id: UUID = UUID(), name: String, tabs: [TabState]) {
        self.id = id
        self.name = name
        self.tabs = tabs
    }
}

/// Workspaces JSON, ghi atomic. Xoá workspace chỉ sửa JSON, không đụng file người dùng.
public final class WorkspaceStore {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pinax", isDirectory: true)
            .appendingPathComponent("workspaces.json")
    }

    public let url: URL
    private let lock = NSLock()
    private var _items: [Workspace] = []

    public var all: [Workspace] { lock.withLock { _items } }

    public init(url: URL = WorkspaceStore.defaultURL) {
        self.url = url
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? JSONDecoder().decode([Workspace].self, from: data) {
            _items = decoded
        } else {
            // File hỏng: để nguyên bản cũ bên cạnh thay vì ghi đè.
            let backup = url.deletingLastPathComponent().appendingPathComponent("workspaces.corrupt.json")
            try? FileManager.default.moveItem(at: url, to: backup)
        }
    }

    @discardableResult
    public func add(name: String, tabs: [TabState]) throws -> Workspace {
        try lock.withLock {
            let w = Workspace(name: name, tabs: tabs)
            _items.append(w)
            try saveLocked()
            return w
        }
    }

    public func rename(id: UUID, to name: String) throws {
        try mutate(id) { $0.name = name }
    }

    public func update(id: UUID, tabs: [TabState]) throws {
        try mutate(id) { $0.tabs = tabs }
    }

    public func delete(id: UUID) throws {
        try lock.withLock {
            _items.removeAll { $0.id == id }
            try saveLocked()
        }
    }

    private func mutate(_ id: UUID, _ change: (inout Workspace) -> Void) throws {
        try lock.withLock {
            guard let i = _items.firstIndex(where: { $0.id == id }) else { return }
            change(&_items[i])
            try saveLocked()
        }
    }

    private func saveLocked() throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try e.encode(_items)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
