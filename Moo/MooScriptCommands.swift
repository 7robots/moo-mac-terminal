//
//  MooScriptCommands.swift
//  Moo
//
//  AppleScript commands declared in Moo.sdef.
//

import AppKit

@objc(OpenTerminalScriptCommand)
final class OpenTerminalScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let directory = directParameter as? String
        WindowOpener.openWindow(spec: LaunchSpec(workingDirectory: directory))
        return nil
    }
}

@objc(OpenTerminalTabScriptCommand)
final class OpenTerminalTabScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        var spec = WindowOpener.inheritedTabSpec()
        if let directory = directParameter as? String, !directory.isEmpty {
            spec.workingDirectory = directory
        }
        WindowOpener.openTab(spec: spec)
        return nil
    }
}

@objc(PreviewMarkdownScriptCommand)
final class PreviewMarkdownScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let path = directParameter as? String, !path.isEmpty else {
            scriptErrorNumber = NSRequiredArgumentsMissingScriptError
            return nil
        }
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            scriptErrorNumber = NSFileNoSuchFileError
            scriptErrorString = "No file at \(url.path)"
            return nil
        }
        guard LinkRouter.isMarkdown(url.path) else {
            scriptErrorNumber = NSArgumentsWrongScriptError
            scriptErrorString = "Not a Markdown file: \(url.lastPathComponent)"
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
        if !MarkdownPreviewOpener.open(fileURL: url, from: nil) {
            scriptErrorNumber = NSInternalScriptError
            scriptErrorString = "No project is open to hold the preview"
        }
        return nil
    }
}

@objc(OpenURLScriptCommand)
final class OpenURLScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let text = directParameter as? String,
              let url = BrowserSession.resolve(input: text) else {
            scriptErrorNumber = NSRequiredArgumentsMissingScriptError
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
        if !BrowserOpener.open(url: url) {
            scriptErrorNumber = NSInternalScriptError
            scriptErrorString = "No project is open to hold the browser tab"
        }
        return nil
    }
}

@objc(SplitPaneScriptCommand)
final class SplitPaneScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let arguments = evaluatedArguments ?? [:]
        let surfaceID = directParameter as? String
        guard let target = PaneScripting.pane(surfaceID: surfaceID),
              let workspace = target.workspace else {
            scriptErrorNumber = NSReceiverEvaluationScriptError
            scriptErrorString = surfaceID.map { "No pane with ID \($0)" } ?? "No terminal pane is open"
            return nil
        }

        var directory: String?
        if let path = arguments["directory"] as? String, !path.isEmpty {
            let expanded = NSString(string: path).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                scriptErrorNumber = NSFileNoSuchFileError
                scriptErrorString = "No folder at \(expanded)"
                return nil
            }
            directory = expanded
        }

        var line: String?
        if let command = arguments["command"] as? String, !command.isEmpty {
            guard let checked = PaneScripting.commandLine(command) else {
                scriptErrorNumber = NSArgumentsWrongScriptError
                scriptErrorString = "The command must be one line, without control characters"
                return nil
            }
            line = checked
        }

        let orientation = PaneScripting.orientation(
            (arguments["direction"] as? NSNumber)?.uint32Value
        )
        let focuses = (arguments["focus"] as? Bool) ?? true
        guard let pane = workspace.split(target,
                                         orientation: orientation,
                                         directory: directory,
                                         focusesNewPane: focuses) else {
            scriptErrorNumber = NSInternalScriptError
            scriptErrorString = "The pane could not be split"
            return nil
        }
        if let line {
            pane.typeWhenStarted(line + "\n")
        }
        return pane.surfaceID
    }
}

/// The parts of the pane commands that do not need a running app.
enum PaneScripting {
    nonisolated static let downCode = fourCharCode("SpDn")

    /// The pane a script names by its MOO_SURFACE_ID, or the focused pane of
    /// the current project when it names none. Hidden workspaces count: a
    /// script running in a background project can still split its own pane.
    static func pane(surfaceID: String?) -> TerminalSessionController? {
        guard let surfaceID, !surfaceID.isEmpty else {
            return ProjectRuntime.shared.selectedSession?.mostRecentTerminalTab?.panes?.focusedController
                ?? TerminalSessionRegistry.shared.controller(for: NSApp.keyWindow ?? NSApp.mainWindow)
        }
        guard let id = UUID(uuidString: surfaceID) else { return nil }
        let windowed = NSApp.windows.flatMap { TerminalSessionRegistry.shared.controllers(for: $0) }
        return (ProjectRuntime.shared.allControllers + windowed).first { $0.id == id }
    }

    /// Right, the default, puts the panes side by side: a vertical divider.
    nonisolated static func orientation(_ code: UInt32?) -> TerminalPaneSplit {
        code == downCode ? .horizontal : .vertical
    }

    /// The command as one typed line, or nil when it holds anything a shell
    /// would act on before its Return: newlines, escapes and other controls,
    /// or the bidirectional overrides that make a line read differently from
    /// what runs.
    nonisolated static func commandLine(_ command: String) -> String? {
        let line = command.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        let refused = line.unicodeScalars.contains { scalar in
            scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
                || (0x202A...0x202E).contains(scalar.value)
                || (0x2066...0x2069).contains(scalar.value)
                || scalar.value == 0x200E || scalar.value == 0x200F
        }
        return refused ? nil : line
    }

    nonisolated static func fourCharCode(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
