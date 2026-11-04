import Foundation

/// Journal JSON, ghi atomic, giữ 50 batch gần nhất.
public final class JournalStore {
    public static let maxBatches = 50

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pinax", isDirectory: true)
            .appendingPathComponent("journal.json")
    }

    public let url: URL
    private let lock = NSLock()
    private var _batches: [Batch] = []

    /// Cũ → mới.
    public var batches: [Batch] { lock.withLock { _batches } }

    /// Batch mới nhất chưa hoàn tác (⌘Z).
    public var latestUndoable: Batch? { batches.last { !$0.undone } }

    public init(url: URL = JournalStore.defaultURL) {
        self.url = url
        load()
    }

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? Self.makeDecoder().decode([Batch].self, from: data) {
            _batches = decoded
        } else {
            // File hỏng: để nguyên bản cũ bên cạnh thay vì ghi đè mất lịch sử.
            let backup = url.deletingLastPathComponent().appendingPathComponent("journal.corrupt.json")
            try? FileManager.default.moveItem(at: url, to: backup)
        }
    }

    public func append(_ batch: Batch) throws {
        try lock.withLock {
            _batches.append(batch)
            if _batches.count > Self.maxBatches { _batches.removeFirst(_batches.count - Self.maxBatches) }
            try saveLocked()
        }
    }

    public func markUndone(_ id: UUID) throws {
        try lock.withLock {
            guard let i = _batches.firstIndex(where: { $0.id == id }) else { return }
            _batches[i].undone = true
            try saveLocked()
        }
    }

    private func saveLocked() throws {
        let data = try Self.makeEncoder().encode(_batches)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
