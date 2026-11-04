import Testing
import Foundation
@testable import PinaxCore

/// Bảng §3.2 của M2, giả lập /Volumes bằng thư mục tạm.
@Suite struct PathGuardVolumesTests {
    let box: Sandbox
    let volumes: URL
    let g: PathGuard

    init() throws {
        box = try Sandbox()
        volumes = box.root.appendingPathComponent("Volumes", isDirectory: true)
        for v in ["Ext", "Startup"] {
            try FileManager.default.createDirectory(at: volumes.appendingPathComponent(v), withIntermediateDirectories: true)
        }
        g = PathGuard(home: box.home, applicationsRoot: box.apps, volumesRoot: volumes,
                      isExternalVolume: { $0.lastPathComponent == "Ext" })
    }

    @Test func allowsStrictlyInsideExternalVolume() {
        #expect(g.isAllowed(volumes.appendingPathComponent("Ext/photo.jpg")))
        #expect(g.isAllowed(volumes.appendingPathComponent("Ext/a/b/c.txt")))
    }

    @Test func deniesVolumeRootAndVolumesRoot() {
        #expect(!g.isAllowed(volumes.appendingPathComponent("Ext")))
        #expect(!g.isAllowed(volumes))
    }

    @Test func deniesNonExternalVolumeContents() {
        #expect(!g.isAllowed(volumes.appendingPathComponent("Startup/x.txt")))
        #expect(!g.isAllowed(volumes.appendingPathComponent("Missing/x.txt")))
    }

    @Test func deniesVolumeOwnTrashAndIndexes() {
        #expect(!g.isAllowed(volumes.appendingPathComponent("Ext/.Trashes/501/x")))
        #expect(!g.isAllowed(volumes.appendingPathComponent("Ext/.Spotlight-V100/x")))
    }

    @Test func deniesSymlinkOnVolumeEscapingToSystem() throws {
        let link = volumes.appendingPathComponent("Ext/escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/etc"))
        #expect(!g.isAllowed(link.appendingPathComponent("hosts")))
    }

    @Test func deniesSystemRootsAndContents() {
        for p in ["/", "/System", "/System/Library/x", "/Library", "/Library/Caches/x", "/usr", "/usr/bin/true",
                  "/bin", "/bin/ls", "/sbin", "/sbin/mount", "/private", "/private/etc/hosts", "/opt",
                  "/opt/homebrew/bin", "/cores", "/cores/core.1"] {
            #expect(!g.isAllowed(URL(fileURLWithPath: p)), "\(p)")
        }
    }

    @Test func homeApplicationsAndTrashRowsUnchanged() {
        #expect(g.isAllowed(box.home.appendingPathComponent("Projects/a.txt")))
        #expect(g.isAllowed(box.apps.appendingPathComponent("Foo.app")))
        #expect(!g.isAllowed(box.apps))
        #expect(!g.isAllowed(box.home.appendingPathComponent(".Trash")))
        #expect(!g.isAllowed(box.home.appendingPathComponent(".Trash/x")))
    }

    @Test func defaultCheckRejectsStartupVolume() {
        #expect(!PathGuard.defaultIsExternalVolume(URL(fileURLWithPath: "/")))
        #expect(!PathGuard.defaultIsExternalVolume(URL(fileURLWithPath: "/definitely/not/here")))
    }
}
