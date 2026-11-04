import SwiftUI
import AppKit
import PinaxCore

@main
struct PinaxApp: App {
    @State private var env = AppEnvironment()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    var body: some Scene {
        WindowGroup("Pinax", id: "browser", for: BrowserSeed.self) { $seed in
            BrowserRoot(seed: seed, env: env)
                .environment(env)
                .environment(env.settings)
                .environment(env.smart)
                .environment(env.tidy)
                .environment(env.history)
                .environment(env.toast)
                .environment(env.favorites)
                .environment(env.volumes)
        } defaultValue: {
            BrowserSeed()
        }
        .defaultSize(width: 1100, height: 720)
        .commands { PinaxCommands(env: env) }

        Settings {
            SettingsView()
                .environment(env)
                .environment(env.settings)
                .frame(width: 560, height: 620)
                .id(env.settings.langPref)
        }
    }
}

struct PinaxCommands: Commands {
    let env: AppEnvironment
    @FocusedValue(\.browser) private var browser
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Đọc langPref để menu được dựng lại khi đổi ngôn ngữ.
        let _ = env.settings.langPref
        CommandGroup(replacing: .undoRedo) {
            Button(L("Undo Last Batch", "Hoàn tác lần dọn gần nhất")) { env.undoLatest() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(env.history.latestUndoable == nil || env.history.isUndoing)
        }
        CommandGroup(after: .newItem) {
            Button(L("New Tab", "Tab mới")) { newTab() }
                .keyboardShortcut("t", modifiers: .command)
            Button(L("Open", "Mở")) { browser?.openSelection() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(browser == nil || browser?.pinax != nil || browser?.selection.isEmpty != false)
            Divider()
            Button(L("Tidy Folder", "Sắp xếp thư mục")) {
                browser?.showPinax(.downloads)
                env.tidyNow()
            }
            .keyboardShortcut("t", modifiers: [.option, .command])
            .disabled(!env.tidy.canTidy)
        }
        CommandMenu(L("Go", "Đi")) {
            Button(L("Back", "Quay lại")) { browser?.back() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(browser?.canGoBack != true)
            Button(L("Forward", "Tiến tới")) { browser?.forward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(browser?.canGoForward != true)
            Button(L("Enclosing Folder", "Thư mục cha")) { browser?.up() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(browser?.canGoUp != true)
            Divider()
            Button(L("Go to Path…", "Đi tới đường dẫn…")) {
                if browser?.pinax != nil, let b = browser { b.navigate(to: b.folder) }
                browser?.pathEditing = true
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(browser == nil)
            Divider()
            Button(L("Add to Favorites", "Thêm vào Yêu thích")) {
                if let b = browser { env.favorites.add(b.folder) }
            }
            .keyboardShortcut("t", modifiers: [.control, .command])
            .disabled(browser == nil || browser?.pinax != nil)
        }
        CommandGroup(after: .toolbar) {
            Toggle(L("Show Hidden Files", "Hiện file ẩn"), isOn: Binding(
                get: { env.prefs.showHidden }, set: { env.prefs.showHidden = $0 }))
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Toggle(L("Keep Folders on Top", "Thư mục luôn ở trên"), isOn: Binding(
                get: { env.prefs.sort.foldersFirst }, set: { env.prefs.sort.foldersFirst = $0 }))
        }
    }

    private func newTab() {
        TabRequest.prepare()
        openWindow(value: BrowserSeed(path: browser?.folder.path, asTab: true))
    }
}
