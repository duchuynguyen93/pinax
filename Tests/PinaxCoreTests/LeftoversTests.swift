import Testing
import Foundation
@testable import PinaxCore

@Suite struct LeftoversTests {
    let box: Sandbox
    let lib: URL
    init() throws {
        box = try Sandbox()
        lib = box.home.appendingPathComponent("Library", isDirectory: true)
    }

    /// Tạo mục và đặt mtime cũ (mặc định 100 ngày trước `testNow`).
    @discardableResult
    func make(_ rel: String, dir: Bool = true, age: Int = 100) throws -> URL {
        let url = lib.appendingPathComponent(rel)
        let fm = FileManager.default
        if dir {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            let inner = url.appendingPathComponent("f")
            try Data([1]).write(to: inner)
            try fm.setAttributes([.modificationDate: daysBefore(age)], ofItemAtPath: inner.path)
        } else {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: url)
        }
        try fm.setAttributes([.modificationDate: daysBefore(age)], ofItemAtPath: url.path)
        return url
    }

    func scan(apps: [InstalledApp] = [], ls: @escaping @Sendable (String) -> Bool = { _ in false },
              spotlight: [InstalledApp] = [], bins: [URL] = []) async -> RuleResult {
        await LeftoversRule(isKnownToLaunchServices: ls, spotlightApps: { spotlight }, binDirs: bins).scan(box.context(apps: apps))
    }

    @Test func flagsOldOrphan() async throws {
        try make("Caches/com.gone.app")
        try make("Preferences/com.gone.app.plist", dir: false)
        try make("Application Support/com.gone.app")
        let r = await scan()
        #expect(paths(r) == ["com.gone.app", "com.gone.app.plist"])
        #expect(r.candidates.count == 3)
        for c in r.candidates {
            #expect(c.reasonKind == .leftover(bundleID: "com.gone.app"))
            #expect(c.reason == "Left by com.gone.app")
            #expect(!c.preselected)
        }
    }

    @Test func skipsInstalledAndHelperOfInstalled() async throws {
        try make("Caches/com.have.app")
        try make("Caches/com.have.app.helper")
        try make("Caches/com.have")
        try make("Caches/com.ls.known")
        let have = try box.fakeApp("Have", bundleID: "com.Have.App")
        let r = await scan(apps: [have], ls: { $0 == "com.ls.known" })
        #expect(r.candidates.isEmpty)
    }

    @Test func skipsAppleAndPinax() async throws {
        try make("Caches/com.apple.Safari")
        try make("Caches/COM.APPLE.thing")
        try make("Caches/\(PathGuard.pinaxBundleID)")
        try make("Caches/\(PathGuard.pinaxBundleID).helper")
        try make("Preferences/\(PathGuard.pinaxBundleID).plist", dir: false)
        let r = await scan()
        #expect(r.candidates.isEmpty)
    }

    @Test func skipsRecentlyModifiedAndInvalidNames() async throws {
        try make("Caches/com.new.app", age: 5)
        try make("Caches/com.edge.app", age: 29)
        try make("Caches/Google")
        try make("Caches/foo.bar")
        let r = await scan()
        #expect(r.candidates.isEmpty)
        // đổi ngưỡng
        let r2 = await LeftoversRule(isKnownToLaunchServices: { _ in false }, spotlightApps: { [] }, binDirs: [])
            .scan(box.context(settings: { $0.leftoverDays = 3 }))
        #expect(paths(r2) == ["com.new.app", "com.edge.app"])
    }

    @Test func launchAgentOnlyWhenProgramMissing() async throws {
        let existing = try box.write("agent-bin", in: box.root)
        func plist(_ name: String, _ dict: [String: Any]) throws {
            let url = try make("LaunchAgents/\(name)", dir: false)
            try (dict as NSDictionary).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: daysBefore(100)], ofItemAtPath: url.path)
        }
        try plist("com.gone.alive.plist", ["Label": "x", "Program": existing.path])
        try plist("com.gone.alive2.plist", ["Label": "x", "ProgramArguments": [existing.path, "-x"]])
        try plist("com.gone.dead.plist", ["Label": "x", "ProgramArguments": ["/nonexistent/pinax-qa-bin"]])
        try plist("com.gone.dead2.plist", ["Label": "x", "Program": "/nonexistent/other"])
        try make("LaunchAgents/com.gone.broken.plist", dir: false) // không phải plist → bỏ qua
        let r = await scan()
        #expect(paths(r) == ["com.gone.dead.plist", "com.gone.dead2.plist"])
    }

    @Test func neverTouchesContainers() async throws {
        try make("Containers/com.gone.app")
        try make("Group Containers/ABCDE12345.com.gone")
        try make("Group Containers/group.com.gone.app")
        let r = await scan()
        #expect(r.candidates.isEmpty)
    }

    @Test func allLocationsCovered() async throws {
        try make("Preferences/ByHost/com.gone.app.12345678-ABCD-1234-ABCD-1234567890AB.plist", dir: false)
        try make("Saved Application State/com.gone.app.savedState")
        try make("HTTPStorages/com.gone.app")
        try make("WebKit/com.gone.app")
        try make("Logs/com.gone.app")
        try make("Cookies/com.gone.app.binarycookies", dir: false)
        let r = await scan()
        #expect(r.candidates.count == 6)
        #expect(Set(r.candidates.map(\.reasonKind)) == [.leftover(bundleID: "com.gone.app")])
    }

    @Test func oldSettingsJSONStillDecodes() throws {
        let s = CleanSettings.defaults(home: box.home)
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        obj.removeValue(forKey: "leftoverDays")
        let decoded = try JSONDecoder().decode(CleanSettings.self, from: JSONSerialization.data(withJSONObject: obj))
        #expect(decoded.leftoverDays == 30)
        #expect(decoded == s)
    }

    // MARK: - Predicates

    @Test func vendorOf() {
        #expect(LeftoverGuards.vendor(of: "com.Google.Chrome") == "google")
        #expect(LeftoverGuards.vendor(of: "ru.keepcoder.Telegram") == "keepcoder")
        #expect(LeftoverGuards.vendor(of: "jetbrains.py.251") == "jetbrains")
        #expect(LeftoverGuards.vendor(of: "org.python.python") == "python")
    }

    @Test func vendorMatchRules() {
        #expect(LeftoverGuards.vendorMatches("jetbrains.ws.251", installedIDs: ["com.jetbrains.pycharm"]))
        #expect(LeftoverGuards.vendorMatches("com.google.Chrome.helper", installedIDs: ["com.google.chrome"]))
        #expect(!LeftoverGuards.vendorMatches("com.other.app", installedIDs: ["com.jetbrains.pycharm"]))
        // electron / todesktop không phải vendor
        #expect(!LeftoverGuards.vendorMatches("com.electron.dockerdesktop", installedIDs: ["com.electron.other"]))
        #expect(!LeftoverGuards.vendorMatches("com.todesktop.123", installedIDs: ["com.todesktop.456"]))
    }

    @Test func nameTokens() {
        let docker = InstalledApp(url: URL(fileURLWithPath: "/Applications/Docker.app"), bundleID: "com.docker.docker", name: "Docker")
        let ab = InstalledApp(url: URL(fileURLWithPath: "/Applications/ab.app"), bundleID: nil, name: "ab")
        let tokens = LeftoverGuards.nameTokens(of: [docker, ab])
        #expect(tokens == ["docker"])
        #expect(LeftoverGuards.nameTokenMatches("com.electron.dockerdesktop", tokens: tokens))
        #expect(!LeftoverGuards.nameTokenMatches("com.other.thing", tokens: tokens))
        let spaced = InstalledApp(url: URL(fileURLWithPath: "/Applications/Telegram Lite.app"), bundleID: nil, name: "Telegram")
        #expect(LeftoverGuards.nameTokenMatches("ru.keepcoder.Telegram", tokens: LeftoverGuards.nameTokens(of: [spaced])))
    }

    @Test func cliTool() throws {
        let bin = box.root.appendingPathComponent("fakebin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let exe = bin.appendingPathComponent("codex")
        try Data("#!/bin/sh\n".utf8).write(to: exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        let plain = bin.appendingPathComponent("notexec")
        try Data([1]).write(to: plain)
        #expect(LeftoverGuards.isCLITool("com.openai.codex", binDirs: [bin]))
        #expect(!LeftoverGuards.isCLITool("com.openai.codex", binDirs: []))
        #expect(!LeftoverGuards.isCLITool("com.x.notexec", binDirs: [bin]))
        // vendor và TLD không được dùng để khớp
        let vend = bin.appendingPathComponent("openai")
        try Data("x".utf8).write(to: vend)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: vend.path)
        #expect(!LeftoverGuards.isCLITool("com.openai.zzz", binDirs: [bin]))
    }

    @Test func denylist() {
        for id in ["com.apple.x", "ORG.CUPS.PrintingPrefs", "org.openssh.agent", "com.microsoft.autoupdate2",
                   "com.google.Keystone.Agent", "com.google.GoogleUpdater", "com.adobe.ACCC", "com.adobe.ccxprocess"] {
            #expect(LeftoverGuards.isDenylisted(id), "\(id)")
        }
        #expect(!LeftoverGuards.isDenylisted("com.google.Chrome"))
    }

    @Test func recentContentWalk() throws {
        let dir = try make("Application Support/walk", age: 100)
        let deep = dir.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        let old = daysBefore(100)
        for u in [dir.appendingPathComponent("a"), deep, dir] { try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: u.path) }
        let cutoff = daysBefore(30)
        #expect(!LeftoverGuards.hasRecentContent(dir, since: cutoff))
        let f = deep.appendingPathComponent("new.txt")
        try Data([1]).write(to: f)
        try FileManager.default.setAttributes([.modificationDate: daysBefore(1)], ofItemAtPath: f.path)
        #expect(LeftoverGuards.hasRecentContent(dir, since: cutoff))
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: f.path)
        for u in [deep, dir.appendingPathComponent("a"), dir] { try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: u.path) }
        #expect(!LeftoverGuards.hasRecentContent(dir, since: cutoff))
        // chạm giới hạn → coi là mới
        #expect(LeftoverGuards.hasRecentContent(dir, since: cutoff, maxEntries: 2))
    }

    @Test func spotlightParse() {
        let text = "/Applications/Python 3.12/IDLE.app   kMDItemCFBundleIdentifier = org.python.IDLE\0"
            + "/x/Foo.App   kMDItemCFBundleIdentifier = (null)\0/y/Bar   kMDItemCFBundleIdentifier = com.bar\0"
            + "/Applications/Docker.app   kMDItemCFBundleIdentifier = com.docker.docker\0"
        let apps = SpotlightInstalledApps.parse(text)
        #expect(apps.map(\.bundleID) == ["org.python.IDLE", "com.docker.docker"])
        #expect(apps.map(\.name) == ["IDLE", "Docker"])
    }

    // MARK: - End to end

    @Test func dockerNameTokenSkips() async throws {
        try make("Caches/com.electron.dockerdesktop")
        let docker = try box.fakeApp("Docker", bundleID: "com.docker.docker")
        let r = await scan(apps: [docker])
        #expect(r.candidates.isEmpty)
        let r2 = await scan()
        #expect(paths(r2) == ["com.electron.dockerdesktop"])
    }

    @Test func vendorSiblingAndSpotlightSkip() async throws {
        try make("Caches/jetbrains.py.251")
        try make("Caches/org.python.python")
        let sp = [InstalledApp(url: URL(fileURLWithPath: "/x/Pycharm.app"), bundleID: "com.jetbrains.pycharm", name: "PyCharm"),
                  InstalledApp(url: URL(fileURLWithPath: "/Library/Frameworks/Python.framework/Python.app"), bundleID: "org.python.python", name: "Python")]
        let r = await scan(spotlight: sp)
        #expect(r.candidates.isEmpty)
        let r2 = await scan()
        #expect(paths(r2) == ["jetbrains.py.251", "org.python.python"])
    }

    @Test func cliBinarySkipsEndToEnd() async throws {
        try make("Caches/com.openai.codex")
        let bin = box.root.appendingPathComponent("bin2", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let exe = bin.appendingPathComponent("codex")
        try Data("x".utf8).write(to: exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        let r = await scan(bins: [bin])
        #expect(r.candidates.isEmpty)
        let r2 = await scan()
        #expect(r2.candidates.count == 1)
    }

    @Test func denylistEndToEnd() async throws {
        try make("Preferences/org.cups.PrintingPrefs.plist", dir: false)
        try make("Caches/com.microsoft.autoupdate2")
        try make("Caches/com.google.Keystone.Agent")
        let r = await scan()
        #expect(r.candidates.isEmpty)
    }

    @Test func deepRecentFileInApplicationSupportSkips() async throws {
        let dir = try make("Application Support/com.gone.deep")
        let deep = dir.appendingPathComponent("x/y", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        let recent = deep.appendingPathComponent("recent.db")
        try Data([1]).write(to: recent)
        try FileManager.default.setAttributes([.modificationDate: daysBefore(1)], ofItemAtPath: recent.path)
        for u in [deep, dir.appendingPathComponent("x")] { try FileManager.default.setAttributes([.modificationDate: daysBefore(100)], ofItemAtPath: u.path) }
        try FileManager.default.setAttributes([.modificationDate: daysBefore(100)], ofItemAtPath: dir.path)
        try make("Caches/com.gone.deep2")
        let r = await scan()
        #expect(paths(r) == ["com.gone.deep2"])
    }
}
