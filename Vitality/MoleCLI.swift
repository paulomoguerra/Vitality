import AppKit
import Foundation

enum MoleError: LocalizedError, Equatable {
    case notInstalled
    case launchFailed(String)
    case failed(exit: Int32, stderr: String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Mole isn't installed. Run `brew install mole` in Terminal."
        case .launchFailed(let why):
            return "Couldn't start Mole: \(why)"
        case .failed(let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "Mole exited with code \(code)." : detail
        case .decodeFailed(let why):
            return "Couldn't read Mole's output: \(why)"
        }
    }
}

/// Single entry point for talking to the `mo` command-line tool.
///
/// Vitality never bundles or links Mole — it shells out to whatever the user
/// installed via Homebrew and parses the public JSON output. Keeping every
/// invocation behind this one type is what keeps that boundary obvious.
enum MoleCLI {
    static let candidatePaths = [
        "/opt/homebrew/bin/mo",   // Apple silicon Homebrew
        "/usr/local/bin/mo",      // Intel Homebrew
    ]

    static var executablePath: String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isInstalled: Bool { executablePath != nil }

    static func run(_ arguments: [String], timeout: TimeInterval = 30) -> Result<Data, MoleError> {
        guard let path = executablePath else { return .failure(.notInstalled) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        // Mole draws ANSI colour and a TUI when it detects a terminal. We're
        // parsing its output, so ask for plain text explicitly.
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }

        // `mo analyze` on a large volume can run for minutes. Without a watchdog
        // a wedged child would block this thread indefinitely.
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let output = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else {
            return .failure(.failed(exit: process.terminationStatus,
                                    stderr: String(decoding: errorOutput, as: UTF8.self)))
        }
        return .success(output)
    }

    static func decode<T: Decodable>(_ type: T.Type, from arguments: [String],
                                     timeout: TimeInterval = 30) -> Result<T, MoleError> {
        run(arguments, timeout: timeout).flatMap { data in
            do {
                return .success(try JSONDecoder().decode(T.self, from: data))
            } catch {
                return .failure(.decodeFailed(error.localizedDescription))
            }
        }
    }

    /// Hands a Mole subcommand off to Terminal. Used for `clean`, `purge` and
    /// `uninstall`, which are interactive TUIs with no JSON or non-interactive
    /// mode — driving them headlessly would mean screen-scraping a UI that can
    /// delete files, so Vitality deliberately doesn't try.
    ///
    /// Writes an executable `.command` file and opens it, rather than using
    /// `NSAppleScript` with `tell application "Terminal"`. AppleScript would
    /// require Automation (Apple Events) consent, and without it the call fails
    /// *silently* — the button appears to do nothing at all. Opening a
    /// `.command` goes through LaunchServices and needs no such permission.
    @discardableResult
    static func runInTerminal(_ subcommand: String) -> Result<Void, ActionError> {
        guard let path = executablePath else {
            return .failure(ActionError("Mole isn't installed. Run `brew install mole` in Terminal."))
        }

        let script = """
        #!/bin/bash
        clear
        echo "Vitality is handing off to Mole — this is Mole's own interactive tool."
        echo
        exec "\(path)" \(subcommand)
        """

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitality-mo-\(subcommand).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: url.path)
        } catch {
            return .failure(ActionError("Couldn't prepare the command: \(error.localizedDescription)"))
        }

        guard NSWorkspace.shared.open(url) else {
            return .failure(ActionError("Couldn't open Terminal to run `mo \(subcommand)`."))
        }
        return .success(())
    }
}
