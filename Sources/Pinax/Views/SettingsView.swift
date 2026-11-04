import SwiftUI
import AppKit
import PinaxCore

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var fdaGranted = FullDiskAccess.isGranted
    @State private var hotKey = HotKeyModel.shared
    @AppStorage(ExternalApps.terminalKey) private var terminalID = ""
    @AppStorage(ExternalApps.editorKey) private var editorID = ""

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section(L("Language", "Ngôn ngữ")) {
                Picker(L("Language", "Ngôn ngữ"), selection: $settings.langPref) {
                    ForEach(LangPref.allCases) { Text($0.label).tag($0) }
                }
            }
            Section(L("Thresholds", "Ngưỡng")) {
                Stepper(value: $settings.clean.largeFileMB, in: 50...100_000, step: 50) {
                    LabeledContent(L("Large file size", "Dung lượng file lớn"), value: "\(settings.clean.largeFileMB) MB")
                }
                days(L("Old downloads", "Tải xuống đã lâu"), $settings.clean.oldDownloadDays)
                days(L("Unused apps", "App lâu không mở"), $settings.clean.unusedAppDays)
                days(L("Screen recordings", "Bản ghi màn hình"), $settings.clean.screenRecordingDays)
                days(L("Stale projects", "Project lâu không đụng"), $settings.clean.staleProjectDays)
            }
            Section(L("Project folders", "Thư mục project")) {
                ForEach(settings.clean.projectRoots, id: \.self) { url in
                    HStack {
                        Text(abbreviate(url))
                        Spacer()
                        Button(role: .destructive) {
                            settings.clean.projectRoots.removeAll { $0 == url }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L("Remove", "Gỡ"))
                    }
                }
                Button(L("Add Folder…", "Thêm thư mục…")) {
                    if let url = pickFolder(), !settings.clean.projectRoots.contains(url) {
                        settings.clean.projectRoots.append(url)
                    }
                }
            }
            Section(L("Tidy folder", "Thư mục sắp xếp")) {
                LabeledContent(L("Folder", "Thư mục"), value: abbreviate(settings.clean.tidyFolder))
                HStack {
                    Button(L("Choose…", "Chọn…")) {
                        if let url = pickFolder() { settings.clean.tidyFolder = url }
                    }
                    Button(L("Use Downloads", "Dùng Downloads")) {
                        settings.clean.tidyFolder = settings.home.appendingPathComponent("Downloads", isDirectory: true)
                    }
                }
            }
            Section(L("Global shortcut", "Phím tắt toàn cục")) {
                Toggle(L("Show Pinax with a shortcut", "Gọi Pinax bằng phím tắt"), isOn: $hotKey.enabled)
                LabeledContent(L("Shortcut", "Phím tắt")) {
                    HStack {
                        Text(hotKey.recording ? L("Press keys…", "Nhấn tổ hợp phím…") : hotKey.display)
                            .monospaced()
                        Button(hotKey.recording ? L("Cancel", "Huỷ") : L("Record Shortcut", "Ghi phím tắt")) {
                            hotKey.recording ? hotKey.endRecording() : hotKey.beginRecording()
                        }
                        Button(L("Reset", "Mặc định")) { hotKey.reset() }
                            .disabled(hotKey.recording)
                    }
                }
                .disabled(!hotKey.enabled)
                if hotKey.enabled && hotKey.status != 0 {
                    Text(L("This shortcut is taken by another app or the system. Pick a different one.",
                           "Phím tắt này đã bị app khác hoặc hệ thống dùng. Hãy chọn tổ hợp khác."))
                        .font(.caption).foregroundStyle(.orange)
                }
                Text(L("Needs ⌘, ⌃ or ⌥. Esc cancels recording.", "Cần ⌘, ⌃ hoặc ⌥. Esc để huỷ ghi."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Open in Terminal / Editor", "Mở trong Terminal / Editor")) {
                appPicker(L("Terminal", "Terminal"), apps: ExternalApps.terminals, selection: $terminalID)
                appPicker(L("Editor", "Editor"), apps: ExternalApps.editors, selection: $editorID)
            }
            Section(L("Permissions", "Quyền truy cập")) {
                LabeledContent("Full Disk Access") {
                    HStack {
                        Image(systemName: fdaGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(fdaGranted ? Color.green : Color.orange)
                        Text(fdaGranted ? L("Granted", "Đã cấp") : L("Not granted", "Chưa cấp"))
                    }
                }
                Text(L("Optional. Needed only to look into Mail attachments. Pinax will not scan them without it.",
                       "Không bắt buộc. Chỉ cần để xem file đính kèm của Mail; không có quyền này thì Pinax bỏ qua mục đó."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L("Open System Settings", "Mở Cài đặt hệ thống")) {
                    NSWorkspace.shared.open(FullDiskAccess.settingsURL)
                }
            }
            Section(L("Trash", "Thùng rác")) {
                Button(L("Open Trash", "Mở Thùng rác")) {
                    NSWorkspace.shared.open(settings.home.appendingPathComponent(".Trash", isDirectory: true))
                }
                Text(L("Pinax never empties the Trash for you.", "Pinax không bao giờ tự đổ Thùng rác."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { fdaGranted = FullDiskAccess.isGranted }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            fdaGranted = FullDiskAccess.isGranted
        }
    }

    @ViewBuilder
    private func appPicker(_ title: String, apps: [CatalogApp], selection: Binding<String>) -> some View {
        if apps.isEmpty {
            LabeledContent(title, value: L("None installed", "Chưa cài app nào"))
        } else {
            let current = apps.contains { $0.bundleID == selection.wrappedValue } ? selection.wrappedValue : apps[0].bundleID
            Picker(title, selection: Binding(get: { current }, set: { selection.wrappedValue = $0 })) {
                ForEach(apps) { Text($0.name).tag($0.bundleID) }
            }
        }
    }

    private func days(_ title: String, _ value: Binding<Int>) -> some View {
        Stepper(value: value, in: 1...3650) {
            LabeledContent(title, value: L("\(value.wrappedValue) days", "\(value.wrappedValue) ngày"))
        }
    }

    private func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("Choose", "Chọn")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
