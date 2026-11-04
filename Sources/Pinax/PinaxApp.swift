import SwiftUI
import PinaxCore

@main
struct PinaxApp: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup("Pinax") {
            ContentView()
                .environment(env)
                .environment(env.settings)
                .environment(env.smart)
                .environment(env.tidy)
                .environment(env.history)
                .environment(env.toast)
                // Đổi ngôn ngữ → dựng lại cây view để mọi L(...) được đánh giá lại.
                .id(env.settings.langPref)
        }
        .defaultSize(width: 1040, height: 720)
        .commands { PinaxCommands(env: env) }
    }
}

struct PinaxCommands: Commands {
    let env: AppEnvironment

    var body: some Commands {
        // Đọc langPref để menu được dựng lại khi đổi ngôn ngữ.
        let _ = env.settings.langPref
        CommandGroup(replacing: .undoRedo) {
            Button(L("Undo Last Batch", "Hoàn tác lần dọn gần nhất")) { env.undoLatest() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(env.history.latestUndoable == nil || env.history.isUndoing)
        }
        CommandGroup(after: .newItem) {
            Button(L("Tidy Folder", "Sắp xếp thư mục")) { env.tidyNow() }
                .keyboardShortcut("t", modifiers: [.option, .command])
                .disabled(!env.tidy.canTidy)
        }
    }
}

struct ContentView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var env = env
        NavigationSplitView {
            SidebarView(selection: $env.section)
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            Group {
                switch env.section {
                case .smartClean: SmartCleanView()
                case .downloads: TidyView()
                case .history: HistoryView()
                case .settings: SettingsView()
                }
            }
            .navigationTitle(env.section.title)
        }
        .frame(minWidth: 900, minHeight: 600)
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 16) }
    }
}
