import Testing
import Foundation
@testable import PinaxCore

@Suite struct PathCommandTests {
    @Test func codeDot() {
        let c = PathCommand.parse("code .")
        #expect(c?.name == "code")
        #expect(c?.argument == ".")
        #expect(c?.target == .apps(["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]))
    }

    @Test func forcedWithoutArgument() {
        let c = PathCommand.parse(">code")
        #expect(c?.name == "code")
        #expect(c?.argument == nil)
    }

    @Test func forcedTrimsAndLowercases() {
        let c = PathCommand.parse("> Code  ~/x")
        #expect(c?.name == "code")
        #expect(c?.argument == "~/x")
    }

    @Test func unknownIsNil() {
        #expect(PathCommand.parse(">unknown") == nil)
        #expect(PathCommand.parse("unknown .") == nil)
    }

    @Test func bareWordIsNotCommand() {
        #expect(PathCommand.parse("zed") == nil)
        #expect(PathCommand.parse("code") == nil)
        #expect(PathCommand.parse("  code  ") == nil)
    }

    @Test func emptyForcedIsNil() {
        #expect(PathCommand.parse(">") == nil)
        #expect(PathCommand.parse(">   ") == nil)
    }

    @Test func specialTargets() {
        #expect(PathCommand.parse(">term")?.target == .terminal)
        #expect(PathCommand.parse("finder .")?.target == .finder)
    }

    @Test func completions() {
        let c = PathCommand.completions(">c")
        #expect(c.contains("code") && c.contains("cursor"))
        #expect(c == c.sorted())
        #expect(PathCommand.completions("x").isEmpty)
        #expect(PathCommand.completions(">code ").isEmpty)
        #expect(PathCommand.completions(">").count == PathCommand.known.count)
    }
}
