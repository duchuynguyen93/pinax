import Testing
import Foundation
@testable import PinaxCore

@Suite struct AppFootprintTests {
    let box: Sandbox
    let lib: URL
    init() throws {
        box = try Sandbox()
        lib = box.home.appendingPathComponent("Library", isDirectory: true)
    }

    @discardableResult
    func make(_ rel: String, dir: Bool = false) throws -> URL {
        let url = lib.appendingPathComponent(rel)
        let fm = FileManager.default
        if dir {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try Data([1]).write(to: url.appendingPathComponent("f"))
        } else {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: url)
        }
        return url
    }

    let app = InstalledApp(url: URL(fileURLWithPath: "/Applications/Foo Bar.app"), bundleID: "com.Foo.App", name: "Foo Bar")
    let uuid = "12345678-ABCD-1234-ABCD-1234567890AB"

    func find(_ items: [FootprintItem], _ rel: String) -> FootprintItem? {
        items.first { $0.url.path == lib.appendingPathComponent(rel).path }
    }

    @Test func everyTableRowMatches() throws {
        let rows = [
            "Application Support/com.foo.app", "Caches/com.foo.app", "Preferences/com.foo.app.plist",
            "Preferences/ByHost/com.foo.app.\(uuid).plist", "Preferences/ByHost/com.foo.app.0123456789AB.plist",
            "Saved Application State/com.foo.app.savedState", "HTTPStorages/com.foo.app",
            "HTTPStorages/com.foo.app.binarycookies", "WebKit/com.foo.app", "Logs/com.foo.app",
            "Cookies/com.foo.app.binarycookies", "LaunchAgents/com.foo.app.plist", "LaunchAgents/com.foo.app.updater.plist",
            "Containers/com.foo.app",
        ]
        for r in rows { try make(r, dir: !r.hasSuffix("plist") && !r.hasSuffix("cookies") && !r.hasSuffix("binarycookies")) }
        let items = AppFootprint.items(for: app, teamID: nil, otherAppsWithSameTeam: false, library: lib)
        for r in rows {
            let item = find(items, r)
            #expect(item != nil, "\(r)")
            #expect(item?.preselected == true, "\(r)")
        }
        #expect(find(items, "LaunchAgents/com.foo.app.updater.plist")?.match == .helper)
        #expect(find(items, "Caches/com.foo.app")?.match == .bundleID)
        #expect(find(items, "Containers/com.foo.app")?.location == "Containers")
    }

    @Test func helperPrefixAndUnrelated() throws {
        try make("Application Support/com.foo.app.helper", dir: true)
        try make("Application Support/com.foo.application", dir: true)
        try make("Caches/com.other.app", dir: true)
        let items = AppFootprint.items(for: app, teamID: nil, otherAppsWithSameTeam: false, library: lib)
        #expect(find(items, "Application Support/com.foo.app.helper")?.match == .helper)
        #expect(find(items, "Application Support/com.foo.application") == nil)
        #expect(find(items, "Caches/com.other.app") == nil)
    }

    @Test func teamGroupNotPreselected() throws {
        try make("Group Containers/ABCDE12345.shared", dir: true)
        try make("Group Containers/ZZZZZ99999.shared", dir: true)
        let items = AppFootprint.items(for: app, teamID: "ABCDE12345", otherAppsWithSameTeam: true, library: lib)
        let g = find(items, "Group Containers/ABCDE12345.shared")
        #expect(g?.match == .teamGroup)
        #expect(g?.preselected == false)
        #expect(find(items, "Group Containers/ZZZZZ99999.shared") == nil)
        // không có team id → bỏ qua Group Containers
        #expect(AppFootprint.items(for: app, teamID: nil, otherAppsWithSameTeam: false, library: lib).isEmpty)
    }

    @Test func nameMatchUntickedAndNoDuplicate() throws {
        try make("Application Support/foo bar", dir: true)
        try make("Caches/FOO BAR", dir: true)
        try make("Logs/Foo Bar", dir: true)
        try make("Preferences/Foo Bar", dir: true) // không thuộc thư mục khớp tên
        let items = AppFootprint.items(for: app, teamID: nil, otherAppsWithSameTeam: false, library: lib)
        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.match == .name && !$0.preselected })
        // tên trùng bundle id → chỉ một mục, loại bundleID
        let named = InstalledApp(url: URL(fileURLWithPath: "/Applications/x.app"), bundleID: "com.x.y", name: "com.x.y")
        try make("Caches/com.x.y", dir: true)
        let i2 = AppFootprint.items(for: named, teamID: nil, otherAppsWithSameTeam: false, library: lib)
        #expect(i2.count == 1 && i2[0].match == .bundleID)
    }

    @Test func shortNamesSkipped() throws {
        try make("Caches/ab", dir: true)
        let short = InstalledApp(url: URL(fileURLWithPath: "/Applications/ab.app"), bundleID: nil, name: "ab")
        #expect(AppFootprint.items(for: short, teamID: nil, otherAppsWithSameTeam: false, library: lib).isEmpty)
    }

    @Test func symlinksNotFollowed() throws {
        let outside = box.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside.appendingPathComponent("com.foo.app"), withIntermediateDirectories: true)
        // thư mục vị trí là symlink
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: lib.appendingPathComponent("Caches"), withDestinationURL: outside)
        // mục là symlink
        try make("Logs/placeholder", dir: true)
        try FileManager.default.createSymbolicLink(at: lib.appendingPathComponent("Logs/com.foo.app"), withDestinationURL: outside)
        #expect(AppFootprint.items(for: app, teamID: nil, otherAppsWithSameTeam: false, library: lib).isEmpty)
    }

    @Test func missingLocationsAreSilent() {
        #expect(AppFootprint.items(for: app, teamID: "T", otherAppsWithSameTeam: false, library: lib).isEmpty)
    }

    @Test func entryNameParsing() {
        let f = AppFootprint.bundleIDFromEntryName
        #expect(f("com.foo.app.plist", "Preferences") == "com.foo.app")
        #expect(f("com.Foo.App.plist", "LaunchAgents") == "com.Foo.App")
        #expect(f("com.foo.app.\(uuid).plist", "Preferences/ByHost") == "com.foo.app")
        #expect(f("com.foo.app.0123456789ab.plist", "Preferences/ByHost") == "com.foo.app")
        #expect(f("com.foo.app.savedState", "Saved Application State") == "com.foo.app")
        #expect(f("com.foo.app.binarycookies", "Cookies") == "com.foo.app")
        #expect(f("com.foo.app.binarycookies", "HTTPStorages") == "com.foo.app")
        #expect(f("com.foo.app", "HTTPStorages") == "com.foo.app")
        #expect(f("com.foo.app", "Caches") == "com.foo.app")
        #expect(f("com.foo.app.PLIST", "Preferences") == "com.foo.app")
        // không hợp lệ
        #expect(f("Google", "Caches") == nil)
        #expect(f("foo.bar", "Caches") == nil)
        #expect(f("com.foo.app", "Preferences") == nil) // thiếu .plist
        #expect(f("com..app", "Caches") == nil)
        #expect(f("com.foo.a pp", "Caches") == nil)
        #expect(f("com.foo.app.txt.plist", "Caches") == "com.foo.app.txt.plist")
    }
}

@Suite struct InstalledBundleIndexTests {
    func app(_ id: String?) -> InstalledApp { InstalledApp(url: URL(fileURLWithPath: "/Applications/X.app"), bundleID: id, name: "X") }

    @Test func matching() {
        let idx = InstalledBundleIndex(apps: [app("com.Foo.App"), app(nil)], launchServices: { _ in false })
        #expect(idx.isInstalled("com.foo.app"))
        #expect(idx.isInstalled("COM.FOO.APP"))
        #expect(idx.isInstalled("com.foo.app.helper"))
        #expect(idx.isInstalled("com.foo")) // tiền tố của app cài
        #expect(!idx.isInstalled("com.foo.application"))
        #expect(!idx.isInstalled("com.fo"))
        #expect(!idx.isInstalled("com.bar.app"))
    }

    @Test func launchServicesStub() {
        let idx = InstalledBundleIndex(apps: [], launchServices: { $0 == "com.ls.known" })
        #expect(idx.isInstalled("com.ls.known"))
        #expect(!idx.isInstalled("com.ls.other"))
    }
}
