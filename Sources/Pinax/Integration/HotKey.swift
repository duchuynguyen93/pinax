import SwiftUI
import AppKit
import Carbon.HIToolbox
import Observation

/// Phím tắt toàn cục qua Carbon `RegisterEventHotKey` (không cần quyền Accessibility).
@MainActor @Observable
final class HotKeyModel {
    static let shared = HotKeyModel()

    private static let enabledKey = "pinax.hotkey.enabled"
    private static let codeKey = "pinax.hotkey.keyCode"
    private static let modsKey = "pinax.hotkey.mods"
    private static let labelKey = "pinax.hotkey.label"

    /// Mặc định ⌥⌘P.
    private static let defaultCode = UInt32(kVK_ANSI_P)
    private static let defaultMods = UInt32(optionKey | cmdKey)

    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey); apply() }
    }
    private(set) var keyCode: UInt32
    private(set) var modifiers: UInt32
    private var keyLabel: String
    /// Kết quả đăng ký gần nhất (noErr = 0).
    private(set) var status: OSStatus = noErr
    private(set) var recording = false

    @ObservationIgnored private var ref: EventHotKeyRef?
    @ObservationIgnored private var handler: EventHandlerRef?
    @ObservationIgnored private var monitor: Any?

    private init() {
        let ud = UserDefaults.standard
        enabled = ud.object(forKey: Self.enabledKey) as? Bool ?? true
        keyCode = ud.object(forKey: Self.codeKey) as? UInt32 ?? Self.defaultCode
        modifiers = ud.object(forKey: Self.modsKey) as? UInt32 ?? Self.defaultMods
        keyLabel = ud.string(forKey: Self.labelKey) ?? "P"
    }

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyLabel
    }

    func start() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { OpenRouter.shared.showOrCreateWindow() }
            return noErr
        }, 1, &spec, nil, &handler)
        apply()
    }

    private func apply() {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        guard enabled else { status = noErr; return }
        let id = EventHotKeyID(signature: OSType(0x50494E58), id: 1) // 'PINX'
        var newRef: EventHotKeyRef?
        status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &newRef)
        if status == noErr { ref = newRef }
        if ProcessInfo.processInfo.environment["PINAX_LOG_HOTKEY"] != nil {
            FileHandle.standardError.write(Data("Pinax hotkey \(display): RegisterEventHotKey status \(status)\n".utf8))
        }
    }

    /// Bắt tổ hợp phím kế tiếp trong app. Esc huỷ; cần ít nhất ⌘, ⌃ hoặc ⌥.
    func beginRecording() {
        guard !recording else { return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) { self.endRecording(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else {
                NSSound.beep()
                return nil
            }
            var mods: UInt32 = 0
            if flags.contains(.command) { mods |= UInt32(cmdKey) }
            if flags.contains(.option) { mods |= UInt32(optionKey) }
            if flags.contains(.control) { mods |= UInt32(controlKey) }
            if flags.contains(.shift) { mods |= UInt32(shiftKey) }
            let label = Self.label(for: event)
            self.keyCode = UInt32(event.keyCode)
            self.modifiers = mods
            self.keyLabel = label
            let ud = UserDefaults.standard
            ud.set(self.keyCode, forKey: Self.codeKey)
            ud.set(mods, forKey: Self.modsKey)
            ud.set(label, forKey: Self.labelKey)
            self.endRecording()
            self.apply()
            return nil
        }
    }

    func endRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    func reset() {
        keyCode = Self.defaultCode
        modifiers = Self.defaultMods
        keyLabel = "P"
        let ud = UserDefaults.standard
        ud.removeObject(forKey: Self.codeKey)
        ud.removeObject(forKey: Self.modsKey)
        ud.removeObject(forKey: Self.labelKey)
        apply()
    }

    private static func label(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            let s = event.charactersIgnoringModifiers?.uppercased() ?? ""
            return s.isEmpty ? "key \(event.keyCode)" : s
        }
    }
}
