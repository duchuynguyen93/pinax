import Foundation
import Observation
import PinaxCore

@MainActor @Observable
final class HistoryModel {
    let store: JournalStore
    /// Mới → cũ.
    private(set) var batches: [Batch] = []
    /// Kết quả từng op sau khi hoàn tác (chỉ trong phiên chạy này).
    private(set) var undoOutcomes: [UUID: [ItemOutcome]] = [:]
    private(set) var isUndoing = false

    init(store: JournalStore) {
        self.store = store
        reload()
    }

    var latestUndoable: Batch? { batches.first { !$0.undone } }

    func reload() { batches = store.batches.reversed() }

    func undo(_ batch: Batch) async -> [ItemOutcome] {
        isUndoing = true
        let store = store
        let outcomes = await Task.detached(priority: .userInitiated) {
            Executor(store: store).undo(batch: batch)
        }.value
        undoOutcomes[batch.id] = outcomes
        reload()
        isUndoing = false
        return outcomes
    }
}
