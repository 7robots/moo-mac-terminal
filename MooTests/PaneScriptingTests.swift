import Foundation
import Testing
@testable import Moo

@MainActor
final class PaneScriptingTests {
    @Test func splitReturnsTheNewPaneAndFocusesIt() {
        let workspace = TerminalPaneWorkspace(startsProcesses: false)
        let first = workspace.controllers[0]
        let pane = workspace.split(first, orientation: .vertical)
        #expect(pane != nil)
        #expect(workspace.paneCount == 2)
        #expect(workspace.focusedController === pane)
        #expect(pane?.workspace === workspace)
    }

    @Test func aSplitCanLeaveTheFocusWhereItWas() {
        let workspace = TerminalPaneWorkspace(startsProcesses: false)
        let first = workspace.controllers[0]
        let revision = workspace.revision
        let pane = workspace.split(first, orientation: .horizontal, focusesNewPane: false)
        #expect(pane != nil)
        #expect(workspace.focusedController === first)
        #expect(workspace.revision == revision + 1)
        guard case .split(let orientation, _, _) = workspace.root.content else {
            Issue.record("root should be a split")
            return
        }
        #expect(orientation == .horizontal)
    }

    @Test func aSplitStartsInTheDirectoryItIsGiven() {
        let workspace = TerminalPaneWorkspace(startsProcesses: false)
        let pane = workspace.split(workspace.controllers[0], orientation: .vertical, directory: "/tmp")
        #expect(pane?.pendingLaunchDirectory == "/tmp")
    }

    @Test func splittingAPaneFromAnotherWorkspaceDoesNothing() {
        let workspace = TerminalPaneWorkspace(startsProcesses: false)
        let other = TerminalPaneWorkspace(startsProcesses: false)
        #expect(workspace.split(other.controllers[0], orientation: .vertical) == nil)
        #expect(workspace.paneCount == 1)
    }

    @Test func directionDefaultsToRight() {
        #expect(PaneScripting.orientation(nil) == .vertical)
        #expect(PaneScripting.orientation(PaneScripting.fourCharCode("SpRt")) == .vertical)
        #expect(PaneScripting.orientation(PaneScripting.fourCharCode("SpDn")) == .horizontal)
    }

    @Test func fourCharCodesMatchTheDictionary() {
        #expect(PaneScripting.fourCharCode("SpDn") == 0x5370_446E)
    }

    @Test func aCommandIsTypedAsOneLine() {
        #expect(PaneScripting.commandLine("  bjorn --note \"a/b\"  ") == "bjorn --note \"a/b\"")
        #expect(PaneScripting.commandLine("   ") == nil)
    }

    @Test func controlCharactersAreRefused() {
        #expect(PaneScripting.commandLine("ls\nrm -rf ~") == nil)
        #expect(PaneScripting.commandLine("ls\r") == nil)
        #expect(PaneScripting.commandLine("echo \u{1b}[31m") == nil)
        #expect(PaneScripting.commandLine("echo \u{202E}txt.sh") == nil)
        #expect(PaneScripting.commandLine("echo \u{9b}") == nil)
    }

    @Test func unknownSurfaceIDsFindNoPane() {
        #expect(PaneScripting.pane(surfaceID: "not-a-uuid") == nil)
        #expect(PaneScripting.pane(surfaceID: UUID().uuidString) == nil)
    }
}
