import Testing
import Foundation
@testable import PinaxCore

@Suite struct DuplicatesRuleTests {
    let box: Sandbox
    init() throws { box = try Sandbox() }
    let mb = 1_048_576

    @Test func groupsAndKeepsMostRecentlyUsed() async throws {
        let a = try box.writeFilled("a.bin", bytes: mb + 10, seed: 1)
        let b = try box.writeFilled("b.bin", bytes: mb + 10, seed: 1)
        let c = try box.writeFilled("c.bin", bytes: mb + 10, seed: 1)
        _ = try box.writeFilled("other.bin", bytes: mb + 10, seed: 2) // cùng size, khác nội dung
        var lu = RuleFixedLastUsed()
        lu.set(b, lastUsed: daysBefore(1))
        lu.set(a, lastUsed: daysBefore(10))
        let r = await DuplicatesRule().scan(box.context(lastUsed: lu))
        #expect(paths(r) == ["a.bin", "c.bin"]) // giữ b
        #expect(r.candidates.allSatisfy { if case let .duplicateOf(k) = $0.reasonKind { return k.resolvingSymlinksInPath().path == b.resolvingSymlinksInPath().path } else { return false } })
        _ = c
    }

    @Test func keeperFallsBackToModificationDate() async throws {
        let old = try box.writeFilled("old.bin", bytes: mb, seed: 3)
        let new = try box.writeFilled("new.bin", bytes: mb, seed: 3)
        try FileManager.default.setAttributes([.modificationDate: daysBefore(30)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: daysBefore(2)], ofItemAtPath: new.path)
        let r = await DuplicatesRule().scan(box.context())
        #expect(paths(r) == ["old.bin"])
    }

    @Test func ignoresSmallFilesAndHardlinks() async throws {
        try box.writeFilled("s1.bin", bytes: mb - 1, seed: 4)
        try box.writeFilled("s2.bin", bytes: mb - 1, seed: 4)
        let big = try box.writeFilled("big.bin", bytes: mb + 5, seed: 5)
        let link = box.downloads.appendingPathComponent("big-hardlink.bin")
        try FileManager.default.linkItem(at: big, to: link)
        let r = await DuplicatesRule().scan(box.context())
        #expect(r.candidates.isEmpty)
    }

    @Test func preselectOnlyWhenAllCopiesInDownloads() async throws {
        let desktop = box.home.appendingPathComponent("Desktop")
        try box.writeFilled("x1.bin", bytes: mb, seed: 6)
        try box.writeFilled("x2.bin", bytes: mb, seed: 6)
        try box.writeFilled("y1.bin", bytes: mb, seed: 7)
        try box.writeFilled("y2.bin", in: desktop, bytes: mb, seed: 7)
        let r = await DuplicatesRule().scan(box.context())
        #expect(r.candidates.count == 2)
        for c in r.candidates {
            let isX = c.url.lastPathComponent.hasPrefix("x")
            #expect(c.preselected == isX, "\(c.url.lastPathComponent)")
        }
    }
}

@Suite struct InstallersRuleTests {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    private func scan(apps: [InstalledApp], mounted: Set<URL> = []) async -> RuleResult {
        await InstallersRule(mounted: NoMountedImages(paths: mounted)).scan(box.context(apps: apps))
    }

    @Test func slackMatchesVSCodeKnownGap() async throws {
        let slack = InstalledApp(url: box.apps.appendingPathComponent("Slack.app"), bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
        let vscode = InstalledApp(url: box.apps.appendingPathComponent("Visual Studio Code.app"), bundleID: "com.microsoft.VSCode", name: "Visual Studio Code")
        try box.write("Slack-4.41.105-macOS.dmg")
        try box.write("Visual Studio Code.zip")
        try box.write("VSCode-darwin-universal.zip") // đã biết: KHÔNG khớp (ghi lại theo plan §5.3)
        try box.write("random.dmg")
        let r = await scan(apps: [slack, vscode])
        #expect(paths(r) == ["Slack-4.41.105-macOS.dmg", "Visual Studio Code.zip"])
    }

    @Test func preselectDmgPkgNotZip() async throws {
        let slack = InstalledApp(url: box.apps.appendingPathComponent("Slack.app"), bundleID: nil, name: "Slack")
        try box.write("Slack-1.0.dmg"); try box.write("Slack-1.0.pkg"); try box.write("Slack-1.0.zip")
        let r = await scan(apps: [slack])
        let sel = Dictionary(uniqueKeysWithValues: r.candidates.map { ($0.url.pathExtension, $0.preselected) })
        #expect(sel == ["dmg": true, "pkg": true, "zip": false])
        #expect(r.candidates.allSatisfy { $0.reasonKind == .installedApp("Slack") })
    }

    @Test func skipsMountedDmgAndNonLevelOne() async throws {
        let slack = InstalledApp(url: box.apps.appendingPathComponent("Slack.app"), bundleID: nil, name: "Slack")
        let mounted = try box.write("Slack-1.0.dmg")
        try box.write("Slack-2.0.dmg", in: box.downloads.appendingPathComponent("sub"))
        let r = await scan(apps: [slack], mounted: [mounted])
        #expect(r.candidates.isEmpty)
    }

    @Test func normalizeAndPrefixRules() {
        #expect(InstallersRule.normalize("Slack-4.41.105-macOS") == "slack")
        #expect(InstallersRule.matches(installer: "figmaplugin", app: "figma")) // tiền tố ≥ 4 ký tự
        #expect(!InstallersRule.matches(installer: "abcdef", app: "abc"))        // < 4 ký tự: chỉ khớp bằng
        #expect(InstallersRule.matches(installer: "abc", app: "abc"))
    }
}

@Suite struct AgeRulesTests {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    @Test func oldDownloadsRespectsThresholdAndNil() async throws {
        let old = try box.write("old.txt"), recent = try box.write("recent.txt")
        let unknown = try box.write("unknown.txt"), mixed = try box.write("mixed.txt")
        let folder = box.downloads.appendingPathComponent("oldfolder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var lu = RuleFixedLastUsed()
        lu.set(old, lastUsed: daysBefore(100))
        lu.set(recent, lastUsed: daysBefore(80))
        lu.set(mixed, lastUsed: daysBefore(10), dateAdded: daysBefore(400)) // max = 10 ngày
        lu.set(folder, dateAdded: daysBefore(91))
        _ = unknown // không có thông tin gì
        let r = await OldDownloadsRule().scan(box.context(lastUsed: lu))
        #expect(paths(r) == ["old.txt", "oldfolder"])
        #expect(r.candidates.allSatisfy { !$0.preselected })
    }

    @Test func unusedAppsNilNeverFlaggedAndAppleSkipped() async throws {
        let stale = try box.fakeApp("Stale", bundleID: "com.example.stale")
        let fresh = try box.fakeApp("Fresh", bundleID: "com.example.fresh")
        let unknown = try box.fakeApp("Unknown", bundleID: "com.example.unknown")
        let apple = try box.fakeApp("Chess", bundleID: "com.apple.Chess")
        let pinax = try box.fakeApp("Pinax", bundleID: PathGuard.pinaxBundleID)
        var lu = RuleFixedLastUsed()
        lu.set(stale.url, lastUsed: daysBefore(181))
        lu.set(fresh.url, lastUsed: daysBefore(179))
        lu.set(apple.url, lastUsed: daysBefore(999))
        lu.set(pinax.url, lastUsed: daysBefore(999))
        let r = await UnusedAppsRule().scan(box.context(lastUsed: lu, apps: [stale, fresh, unknown, apple, pinax]))
        #expect(paths(r) == ["Stale.app"])
        #expect(r.candidates.first?.size ?? 0 > 0)
    }

    @Test func screenRecordings() async throws {
        let desktop = box.home.appendingPathComponent("Desktop")
        let old = try box.write("Screen Recording 2025-01-01.mov", in: desktop)
        let recent = try box.write("Screen Recording 2025-02-02.mov", in: desktop)
        let usedRecently = try box.write("Screen Recording 3.mov", in: desktop)
        let viet = try box.write("Bản ghi màn hình 4.mov", in: desktop)
        try box.write("holiday.mov", in: desktop)
        let extra = try box.write("Screen Recording 5.mov", in: box.home.appendingPathComponent("Captures"))
        try box.write("Screen Recording 6.mp4", in: desktop)
        let fm = FileManager.default
        for (url, days) in [(old, 60), (recent, 5), (usedRecently, 60), (viet, 45), (extra, 90)] {
            try fm.setAttributes([.creationDate: daysBefore(days)], ofItemAtPath: url.path)
        }
        var lu = RuleFixedLastUsed()
        lu.set(usedRecently, lastUsed: daysBefore(3))
        let rule = ScreenRecordingsRule(captureLocation: { "~/Captures" })
        let r = await rule.scan(box.context(lastUsed: lu))
        #expect(paths(r) == ["Screen Recording 2025-01-01.mov", "Bản ghi màn hình 4.mov", "Screen Recording 5.mov"])
    }
}

@Suite struct OtherRulesTests {
    let box: Sandbox
    init() throws { box = try Sandbox() }
    let mb = 1_048_576

    @Test func devCachesOnlyExistingAndAboveThreshold() async throws {
        let derived = box.home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let npm = box.home.appendingPathComponent(".npm/_cacache")
        try box.writeFilled("big", in: derived, bytes: 11 * mb, seed: 1)
        try box.writeFilled("small", in: npm, bytes: mb, seed: 1)
        let r = await DevCachesRule().scan(box.context())
        #expect(paths(r) == ["DerivedData"])
        #expect(r.candidates.first?.preselected == true)
        #expect(r.candidates.first?.size ?? 0 >= Int64(10 * mb))
        let r2 = await DevCachesRule(minBytes: 1000).scan(box.context())
        #expect(paths(r2) == ["DerivedData", "_cacache"])
    }

    @Test func devStaleFindsOnlyOldProjectsAndDeviceSupport() async throws {
        let code = box.home.appendingPathComponent("Code")
        try box.write("x.js", in: code.appendingPathComponent("oldproj/node_modules/pkg"))
        try box.write("y.js", in: code.appendingPathComponent("newproj/node_modules/pkg"))
        try box.write("z.js", in: code.appendingPathComponent("oldproj/node_modules/pkg/node_modules/inner"))
        try box.write("sym", in: box.home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport/17.0 (21A)"))
        try FileManager.default.setAttributes([.modificationDate: daysBefore(200)],
                                              ofItemAtPath: code.appendingPathComponent("oldproj").path)
        let r = await DevStaleRule().scan(box.context { $0.projectRoots = [code] })
        #expect(r.candidates.count == 2)
        let urls = r.candidates.map(\.url.path)
        #expect(urls.contains { $0.hasSuffix("oldproj/node_modules") })
        #expect(urls.contains { $0.hasSuffix("17.0 (21A)") })
    }

    @Test func mailDownloads() async throws {
        let dir = box.home.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
        let missing = await MailDownloadsRule().scan(box.context())
        #expect(missing.candidates.isEmpty)
        if case .ok = missing.status {} else { Issue.record("missing dir should be ok") }

        try box.write("att.pdf", in: dir.appendingPathComponent("UUID"))
        let r = await MailDownloadsRule().scan(box.context())
        #expect(paths(r) == ["UUID"])
        #expect(r.candidates.first?.preselected == true)

        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        let denied = await MailDownloadsRule().scan(box.context())
        guard case .needsFullDiskAccess = denied.status else { Issue.record("expected needsFullDiskAccess, got \(denied.status)"); return }
        #expect(denied.candidates.isEmpty)
    }

    @Test func largeFilesWalkerFallback() async throws {
        let docs = box.home.appendingPathComponent("Docs")
        try box.writeFilled("big.bin", in: docs, bytes: 2 * mb, seed: 1)
        try box.writeFilled("small.bin", in: docs, bytes: mb / 2, seed: 1)
        try box.writeFilled("lib.bin", in: box.home.appendingPathComponent("Library/Foo"), bytes: 2 * mb, seed: 1)
        let pkg = box.home.appendingPathComponent("Pictures/Photos Library.photoslibrary")
        try box.writeFilled("master.bin", in: pkg.appendingPathComponent("originals"), bytes: 2 * mb, seed: 1)
        let r = await LargeFilesRule(spotlight: NoSpotlight()).scan(box.context { $0.largeFileMB = 1 })
        #expect(paths(r) == ["big.bin"])
        #expect(r.candidates.first?.preselected == false)
    }

    @Test func largeFilesFiltersSpotlightHits() async throws {
        let docs = box.home.appendingPathComponent("Docs")
        let big = try box.writeFilled("big.bin", in: docs, bytes: 2 * mb, seed: 1)
        let lib = try box.writeFilled("lib.bin", in: box.home.appendingPathComponent("Library/Foo"), bytes: 2 * mb, seed: 1)
        let ghost = docs.appendingPathComponent("ghost.bin")
        let hits = FixedSpotlight(urls: [big, lib, ghost, docs])
        let r = await LargeFilesRule(spotlight: hits).scan(box.context { $0.largeFileMB = 1 })
        #expect(paths(r) == ["big.bin"])
    }

    @Test func fileSystemInstalledApps() throws {
        let util = box.apps.appendingPathComponent("Utilities")
        for (dir, name, id) in [(box.apps, "Alpha", "com.x.alpha"), (util, "Beta", "com.x.beta")] {
            let contents = dir.appendingPathComponent("\(name).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name]
            try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        }
        // app lồng trong app không được đếm; thư mục sâu 3 không được đếm
        try FileManager.default.createDirectory(at: box.apps.appendingPathComponent("Alpha.app/Contents/Inner.app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: util.appendingPathComponent("deep/deeper/Gamma.app"), withIntermediateDirectories: true)
        let apps = FileSystemInstalledApps(roots: [box.apps]).installedApps()
        #expect(Set(apps.map(\.name)) == ["Alpha", "Beta"])
        #expect(Set(apps.compactMap(\.bundleID)) == ["com.x.alpha", "com.x.beta"])
    }
}

@Suite struct RuleEngineTests {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    @Test func pathOnlyInFirstRuleStubs() async throws {
        let a = try box.write("a.txt"), b = try box.write("b.txt")
        let inner = try box.write("inner.txt", in: box.downloads.appendingPathComponent("folder"))
        let folder = box.downloads.appendingPathComponent("folder")
        let engine = RuleEngine(rules: [StubRule(id: "r1", urls: [a]),
                                        StubRule(id: "r2", urls: [a, b, folder]),
                                        StubRule(id: "r3", urls: [b, inner, folder])])
        let results = await engine.run(box.context())
        #expect(results.map(\.ruleID) == ["r1", "r2", "r3"])
        #expect(results[0].candidates.map(\.url) == [a])
        #expect(Set(results[1].candidates.map(\.url)) == [b, folder])
        #expect(results[2].candidates.isEmpty) // inner nằm trong folder đã được r2 giữ
    }

    @Test func realRulesDedupeInstallerVsOldDownload() async throws {
        let slack = InstalledApp(url: box.apps.appendingPathComponent("Slack.app"), bundleID: nil, name: "Slack")
        let dmg = try box.write("Slack-1.0.dmg"), other = try box.write("notes.txt")
        var lu = RuleFixedLastUsed()
        lu.set(dmg, lastUsed: daysBefore(200))
        lu.set(other, lastUsed: daysBefore(200))
        let engine = RuleEngine(rules: [InstallersRule(mounted: NoMountedImages()), OldDownloadsRule()])
        let results = await engine.run(box.context(lastUsed: lu, apps: [slack]))
        #expect(paths(results[0]) == ["Slack-1.0.dmg"])
        #expect(paths(results[1]) == ["notes.txt"])
    }

    @Test func standardEngineOrderAndEvents() async throws {
        let engine = RuleEngine.standard()
        #expect(engine.rules.map(\.id) == ["devCaches", "devStale", "duplicates", "installers", "mailDownloads",
                                           "largeFiles", "unusedApps", "screenRecordings", "oldDownloads"])
    }

    @Test func cancellationReturnsWithoutCrash() async throws {
        let big = try box.writeFilled("a.bin", bytes: 1_048_576, seed: 1)
        _ = big
        let task = Task { await RuleEngine(rules: [DuplicatesRule(), OldDownloadsRule()]).run(box.context()) }
        task.cancel()
        let results = await task.value
        #expect(results.count == 2)
    }
}

@Suite struct ExecutorHardeningTests {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    @Test func protectedAppBundleIsSkipped() throws {
        let fm = FileManager.default
        func makeApp(_ name: String, id: String) throws -> URL {
            let url = box.apps.appendingPathComponent("\(name).app")
            let contents = url.appendingPathComponent("Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            try ([ "CFBundleIdentifier": id ] as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
            return url
        }
        let apple = try makeApp("Chess", id: "com.apple.Chess")
        let pinax = try makeApp("Pinax", id: PathGuard.pinaxBundleID)
        let normal = try makeApp("Other", id: "com.example.other")
        let r = box.executor().perform(candidates: [box.candidate(apple), box.candidate(pinax), box.candidate(normal)],
                                       title: "t", trasher: TempTrasher(dir: box.trash), home: box.home)
        #expect(r.outcomes.map(\.status) == [.skipped(.protectedPath), .skipped(.protectedPath), .done])
        #expect(fm.fileExists(atPath: apple.path) && fm.fileExists(atPath: pinax.path))
        #expect(!fm.fileExists(atPath: normal.path))
    }
}

@Suite struct SmokeTests {
    /// Chạy RuleEngine trên home THẬT, chỉ đọc (không trash, không ghi). Bật bằng PINAX_SMOKE=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PINAX_SMOKE"] == "1"))
    func realHomeReadOnly() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        let ctx = ScanContext(home: home, applicationRoots: roots, now: Date(),
                              lastUsed: SpotlightLastUsedProvider(),
                              installedApps: FileSystemInstalledApps(roots: roots),
                              settings: .defaults(home: home))
        let start = Date()
        let results = await RuleEngine.standard().run(ctx)
        var total: Int64 = 0
        print("=== PINAX SMOKE (read-only) FDA granted: \(FullDiskAccess.isGranted)")
        for r in results {
            let bytes = r.candidates.reduce(0) { $0 + $1.size }
            total += bytes
            let pre = r.candidates.filter(\.preselected).count
            print("SMOKE \(r.ruleID): count=\(r.candidates.count) preselected=\(pre) bytes=\(bytes) (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))) status=\(r.status)")
            for c in r.candidates.prefix(3) { print("    e.g. \(c.url.lastPathComponent) [\(c.reason)]") }
        }
        print("SMOKE total bytes=\(total) (\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))) in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
    }
}
