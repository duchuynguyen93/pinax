import Foundation
import Observation
import PinaxCore

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    /// Có batch → hiện nút Hoàn tác.
    let undoBatch: Batch?
    let problems: [Problem]
}

@MainActor @Observable
final class ToastModel {
    private(set) var current: Toast?
    /// AppEnvironment gắn vào để thực hiện hoàn tác.
    var undoHandler: ((Batch) -> Void)?

    func show(_ message: String, undoBatch: Batch? = nil, problems: [Problem] = []) {
        let toast = Toast(message: message, undoBatch: undoBatch, problems: problems)
        current = toast
        if problems.isEmpty {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                if self?.current?.id == toast.id { self?.current = nil }
            }
        }
    }

    func dismiss() { current = nil }

    func undoCurrent() {
        guard let batch = current?.undoBatch else { return }
        current = nil
        undoHandler?(batch)
    }
}
