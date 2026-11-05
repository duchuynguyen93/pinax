import Foundation
import Observation
import PinaxCore

/// Danh sách workspace (preset tab + pane). Chỉ ghi JSON, không đụng file người dùng.
@MainActor @Observable
final class WorkspacesModel {
    private(set) var items: [Workspace]
    @ObservationIgnored private let store: WorkspaceStore
    @ObservationIgnored private let toast: ToastModel

    init(toast: ToastModel, store: WorkspaceStore = WorkspaceStore()) {
        self.toast = toast
        self.store = store
        items = store.all
    }

    func add(name: String, tabs: [TabState]) {
        attempt { _ = try store.add(name: name, tabs: tabs) }
    }

    func rename(_ id: UUID, to name: String) {
        attempt { try store.rename(id: id, to: name) }
    }

    func update(_ id: UUID, tabs: [TabState]) {
        attempt { try store.update(id: id, tabs: tabs) }
    }

    func delete(_ id: UUID) {
        attempt { try store.delete(id: id) }
    }

    private func attempt(_ change: () throws -> Void) {
        do { try change() } catch {
            toast.show(L("Couldn't save workspaces: \(error.localizedDescription)",
                         "Không lưu được workspace: \(error.localizedDescription)"))
        }
        items = store.all
    }
}
