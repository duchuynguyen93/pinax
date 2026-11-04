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
                editor.selectedRange = NSRange(location: (initialText as NSString).length, length: 0)
            }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) { context.coordinator.parent = self }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PathField
        private var cycle: (matches: [String], index: Int)?
        private var finished = false
        private let home = FileManager.default.homeDirectoryForCurrentUser

        init(_ parent: PathField) { self.parent = parent }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                tab(textView)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
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
            guard !finished else { return }
            finished = true
            parent.onCancel()
        }

        private func tab(_ tv: NSTextView) {
            let text = tv.string
            if var c = cycle, c.matches.indices.contains(c.index), c.matches[c.index] == text {
                c.index = (c.index + 1) % c.matches.count
                cycle = c
                set(tv, c.matches[c.index])
                parent.onSuggestions(c.matches, c.index)
                return
            }
            let matches = PathCompletion.complete(text, home: home)
            guard !matches.isEmpty else {
                NSSound.beep()
                parent.onSuggestions([], nil)
                return
            }
            if matches.count == 1 {
                cycle = nil
                set(tv, matches[0])
                parent.onSuggestions([], nil)
                return
            }
            let common = Self.commonPrefix(matches)
            if common.count > text.count {
                cycle = nil
                set(tv, common)
                parent.onSuggestions(matches, nil)
            } else {
                cycle = (matches, 0)
                set(tv, matches[0])
                parent.onSuggestions(matches, 0)
            }
        }

        private func set(_ tv: NSTextView, _ s: String) {
            tv.string = s
            tv.setSelectedRange(NSRange(location: (s as NSString).length, length: 0))
        }

        private static func commonPrefix(_ list: [String]) -> String {
            var prefix = Substring(list[0])
            for s in list.dropFirst() {
                while !prefix.isEmpty, !s.lowercased().hasPrefix(prefix.lowercased()) { prefix = prefix.dropLast() }
            }
            return String(prefix)
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
