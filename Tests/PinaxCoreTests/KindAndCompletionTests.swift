import Testing
import Foundation
import UniformTypeIdentifiers
@testable import PinaxCore

@Suite struct KindTextTests {
    @Test func capitalizesFirstCharacterOnly() {
        #expect(FileItem.capitalizingFirst("folder", locale: Locale(identifier: "en_US")) == "Folder")
        #expect(FileItem.capitalizingFirst("PDF document", locale: Locale(identifier: "en_US")) == "PDF document")
        #expect(FileItem.capitalizingFirst("", locale: Locale(identifier: "en_US")) == "")
        #expect(FileItem.capitalizingFirst("thư mục", locale: Locale(identifier: "vi_VN")) == "Thư mục")
    }

    @Test func folderAndAppKinds() {
        let folder = FileItem.kindText(isDirectory: true, isPackage: false, ext: "")
        #expect(folder.first?.isUppercase == true)
        // Package có đuôi .app phải ra UTType application-bundle, không phải "Package" chung.
        #expect(FileItem.contentType(isDirectory: true, isPackage: true, ext: "app") != .package)
        let app = FileItem.kindText(isDirectory: true, isPackage: true, ext: "app")
        #expect(app == "Application")
        // Package lạ → rơi về Package chung.
        #expect(FileItem.contentType(isDirectory: true, isPackage: true, ext: "zzqqx") == .package)
        #expect(FileItem.contentType(isDirectory: true, isPackage: true, ext: "") == .package)
    }

    @Test func listedAppIsApplication() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pinax-kind-\(UUID().uuidString)")
        let app = dir.appendingPathComponent("Thing.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let item = try #require(FileItem.listed(app))
        #expect(item.isPackage)
        #expect(item.kindDescription == "Application")
    }
}

@Suite struct TabCompletionStepTests {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    private func mkdir(_ rel: String) throws {
        try FileManager.default.createDirectory(at: box.home.appendingPathComponent(rel), withIntermediateDirectories: true)
    }

    @Test func uniqueMatchKeepsTilde() throws {
        try mkdir("Code/Personal")
        try mkdir("Code/Work")
        let s = PathCompletion.step(text: "~/Code/Pers", home: box.home, cycle: nil)
        #expect(s?.text == "~/Code/Personal/")
    }

    @Test func commonPrefixThenCycleForwardAndBack() throws {
        try mkdir("Code/Alpha1")
        try mkdir("Code/Alpha2")
        let first = try #require(PathCompletion.step(text: "~/Code/Al", home: box.home, cycle: nil))
        #expect(first.text == "~/Code/Alpha" && first.index == nil && first.matches.count == 2)
        let second = try #require(PathCompletion.step(text: first.text, home: box.home, cycle: nil))
        #expect(second.text == "~/Code/Alpha1/" && second.index == 0)
        let third = try #require(PathCompletion.step(text: second.text, home: box.home, cycle: (second.matches, 0)))
        #expect(third.text == "~/Code/Alpha2/")
        let back = try #require(PathCompletion.step(text: third.text, home: box.home, cycle: (third.matches, 1), backwards: true))
        #expect(back.text == "~/Code/Alpha1/")
    }

    @Test func noMatchReturnsNil() {
        #expect(PathCompletion.step(text: "~/zzzz-nothing", home: box.home, cycle: nil) == nil)
    }
}
