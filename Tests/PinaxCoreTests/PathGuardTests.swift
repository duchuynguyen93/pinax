import Testing
import Foundation
@testable import PinaxCore

@Suite struct PathGuardTests {
    let box: Sandbox
    let g: PathGuard

    init() throws {
        box = try Sandbox()
        g = PathGuard(home: box.home, applicationsRoot: box.apps)
    }

    @Test func deniesExactPaths() {
        let h = box.home
        let denied: [URL] = [
            URL(fileURLWithPath: "/"), URL(fileURLWithPath: "/System"), URL(fileURLWithPath: "/Library"),
            box.apps, h,
            h.appendingPathComponent("Library"), h.appendingPathComponent("Desktop"),
            h.appendingPathComponent("Documents"), h.appendingPathComponent("Downloads"),
            h.appendingPathComponent("Movies"), h.appendingPathComponent("Pictures"),
            h.appendingPathComponent("Music"), h.appendingPathComponent(".Trash"),
            h.appendingPathComponent("Library/Mobile Documents"),
        ]
        for u in denied { #expect(!g.isAllowed(u), "\(u.path)") }
    }

    @Test func deniesTrashContentsAndICloudContainers() {
        let h = box.home
        #expect(!g.isAllowed(h.appendingPathComponent(".Trash/foo.txt")))
        #expect(!g.isAllowed(h.appendingPathComponent(".Trash/a/b/c.txt")))
        #expect(!g.isAllowed(h.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")))
        // Bên trong container (cấp sâu hơn) vẫn được phép.
        #expect(g.isAllowed(h.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/x.txt")))
    }

    @Test func allowsStrictlyInsideHomeAndApplications() {
        #expect(g.isAllowed(box.home.appendingPathComponent("Downloads/a.dmg")))
        #expect(g.isAllowed(box.home.appendingPathComponent("Library/Caches/foo")))
        #expect(g.isAllowed(box.apps.appendingPathComponent("Foo.app")))
    }

    @Test func deniesOutsideHomeAndApplications() {
        #expect(!g.isAllowed(URL(fileURLWithPath: "/etc/hosts")))
        #expect(!g.isAllowed(URL(fileURLWithPath: "/usr/bin/true")))
        #expect(!g.isAllowed(box.root.appendingPathComponent("faketrash/x")))
        // Tiền tố giống tên nhưng khác thư mục.
        #expect(!g.isAllowed(URL(fileURLWithPath: box.home.path + "-other/file")))
    }

    @Test func deniesSymlinkEscapingHome() throws {
        let link = box.downloads.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/etc"))
        #expect(!g.isAllowed(link))
        #expect(!g.isAllowed(link.appendingPathComponent("hosts")))
    }

    @Test func deniesSymlinkResolvingToProtectedFolder() throws {
        let link = box.downloads.appendingPathComponent("toDocs")
        let docs = box.home.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: docs)
        #expect(!g.isAllowed(link))
    }

    @Test func caseInsensitiveDenyAndDotDot() {
        #expect(!g.isAllowed(box.home.appendingPathComponent("downloads")))
        #expect(!g.isAllowed(box.home.appendingPathComponent("Downloads/../Documents")))
        #expect(!g.isAllowed(box.home.appendingPathComponent("Downloads/..")))
    }

    @Test func protectedApps() {
        #expect(PathGuard.isProtectedApp(bundleID: "com.apple.Safari"))
        #expect(PathGuard.isProtectedApp(bundleID: "COM.APPLE.finder"))
        #expect(PathGuard.isProtectedApp(bundleID: "com.duchuynguyen93.pinax"))
        #expect(!PathGuard.isProtectedApp(bundleID: "com.tinyspeck.slackmacgap"))
        #expect(!PathGuard.isProtectedApp(bundleID: nil))
    }
}
