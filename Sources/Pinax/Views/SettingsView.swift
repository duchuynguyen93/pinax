import SwiftUI
import AppKit
import PinaxCore

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var fdaGranted = FullDiskAccess.isGranted

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
