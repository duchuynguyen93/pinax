import SwiftUI
import AppKit
import PinaxCore

/// Ô gõ đường dẫn của ⌘L: Tab hoàn thành (bấm lại để xoay vòng), Return đi, Esc huỷ.
struct PathField: NSViewRepresentable {
    let initialText: String
    /// Trả false nếu đường dẫn không đi được → ô lắc và đỏ chữ.
    let onSubmit: (String) -> Bool
    let onCancel: () -> Void
    let onSuggestions: ([String], Int?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: initialText)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.wantsLayer = true
        field.lineBreakMode = .byTruncatingHead
        DispatchQueue.main.async {
            guard let window = field.window else { return }
            window.makeFirstResponder(field)
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: 0, length: (initialText as NSString).length) // chọn hết → gõ là thay
            }
        }
        context.coordinator.installTabMonitor(for: field)
        return field
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) { coordinator.removeTabMonitor() }

    func updateNSView(_ field: NSTextField, context: Context) { context.coordinator.parent = self }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PathField
        private var cycle: (matches: [String], index: Int)?
        private var finished = false
        private let home = FileManager.default.homeDirectoryForCurrentUser

        init(_ parent: PathField) { self.parent = parent }

        /// SwiftUI dùng Tab để chuyển focus nên `insertTab:` không tới được field editor.
        /// Bắt Tab / ⇧Tab ở tầng sự kiện khi ô này đang được gõ.
        private var tabMonitor: Any?

        func installTabMonitor(for field: NSTextField) {
            removeTabMonitor()
            tabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak field] event in
                guard let self, let field, event.keyCode == 48, // Tab
                      let tv = field.currentEditor() as? NSTextView, field.window?.firstResponder === tv,
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
                self.tab(tv, backwards: event.modifierFlags.contains(.shift))
                return nil
            }
        }

        func removeTabMonitor() {
            if let m = tabMonitor { NSEvent.removeMonitor(m) }
            tabMonitor = nil
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                tab(textView, backwards: false)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                tab(textView, backwards: true)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                if parent.onSubmit(textView.string) {
                    finished = true
                } else {
                    reject(control as? NSTextField)
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                finish()
                return true
            default:
                return false
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            cycle = nil
            parent.onSuggestions([], nil)
            if let field = obj.object as? NSTextField, field.textColor == .systemRed {
                field.textColor = .labelColor
                (field.currentEditor() as? NSTextView)?.textColor = .labelColor
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) { finish() } // mất focus = huỷ

        private func finish() {
            removeTabMonitor()
            guard !finished else { return }
            finished = true
            parent.onCancel()
        }

        private func tab(_ tv: NSTextView, backwards: Bool) {
            guard let step = PathCompletion.step(text: tv.string, home: home, cycle: cycle, backwards: backwards) else {
                NSSound.beep()
                parent.onSuggestions([], nil)
                return
            }
            cycle = step.index.map { (step.matches, $0) }
            set(tv, step.text)
            parent.onSuggestions(step.matches, step.index)
        }

        private func set(_ tv: NSTextView, _ s: String) {
            tv.string = s
            tv.setSelectedRange(NSRange(location: (s as NSString).length, length: 0))
        }

        private func reject(_ field: NSTextField?) {
            guard let field else { return }
            NSSound.beep()
            field.textColor = .systemRed
            (field.currentEditor() as? NSTextView)?.textColor = .systemRed
            let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
            shake.values = [0, -8, 8, -6, 6, -3, 3, 0]
            shake.duration = 0.4
            field.layer?.add(shake, forKey: "shake")
        }
    }
}
