import AppKit
import Darwin
import Foundation

struct ProcessIdentity: Hashable {
    let pid: Int32
    let startTime: UInt64?
}

struct RunningProcess: Identifiable, Hashable {
    let pid: Int32
    let uid: uid_t
    let startTime: UInt64?
    let cpu: Double
    let memoryBytes: Int64
    let name: String

    var id: ProcessIdentity { ProcessIdentity(pid: pid, startTime: startTime) }

    /// You can only signal your own processes without elevating. Knowing this
    /// up front lets the UI explain why a Quit button is disabled instead of
    /// letting the user click it and watch nothing happen.
    var isOwnedByCurrentUser: Bool { uid == getuid() }
}

enum ProcessManager {

    /// Reads `ps` rather than `libproc` because the per-process CPU percentage
    /// `ps` reports is already the smoothed figure users recognise from
    /// Activity Monitor; computing it from raw `proc_pidinfo` counters would
    /// mean reimplementing that smoothing to get the same numbers.
    /// Loads the complete process table for the dashboard.
    static func listAll() -> [RunningProcess] {
        readProcesses(limit: nil)
    }

    /// Loads an explicit top-N slice for compact metrics, such as the five
    /// processes shown in the menu bar. There is intentionally no default:
    /// callers must state when they want a limited result.
    static func list(limit: Int) -> [RunningProcess] {
        readProcesses(limit: limit)
    }

    private static func readProcesses(limit: Int?) -> [RunningProcess] {
        guard limit == nil || limit! > 0 else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        // -r sorts by current CPU. `=` suffixes suppress the header row.
        process.arguments = ["-Axcro", "pid=,uid=,pcpu=,rss=,comm="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(decoding: data, as: UTF8.self)
        var result: [RunningProcess] = []

        for line in text.split(separator: "\n") {
            // Split into at most 5 fields so process names containing spaces
            // survive intact in the final component.
            let parts = line.split(maxSplits: 4, whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
                .filter { !$0.isEmpty }
            guard parts.count >= 5,
                  let pid = Int32(parts[0]),
                  let uid = uid_t(parts[1]),
                  let cpu = Double(parts[2]),
                  let rssKB = Int64(parts[3])
            else { continue }

            result.append(RunningProcess(
                pid: pid,
                uid: uid,
                startTime: processSnapshot(for: pid)?.startTime,
                cpu: cpu,
                memoryBytes: rssKB * 1024,   // ps reports RSS in kilobytes
                name: parts[4]
            ))
            if let limit, result.count >= limit { break }
        }
        return result
    }

    /// Asks a process to quit. `force` escalates to SIGKILL, which gives the
    /// app no chance to save state — so the UI keeps that behind a separate,
    /// explicit choice rather than making it the default. The process start
    /// time is checked again first so a recycled PID is never trusted solely
    /// because its number still appears in the table.
    @discardableResult
    static func terminate(_ process: RunningProcess, force: Bool = false) -> Result<Void, ActionError> {
        let pid = process.pid
        guard pid > 0 else { return .failure(ActionError("Invalid process ID.")) }
        if pid == getpid() { return .failure(ActionError("Vitality can't quit itself.")) }

        guard let expectedStartTime = process.startTime,
              let current = processSnapshot(for: pid)
        else {
            return .failure(ActionError("Couldn't verify that process safely. Refresh the table and try again."))
        }

        guard current.startTime == expectedStartTime,
              current.uid == process.uid
        else {
            return .failure(ActionError("That process changed or already exited. Refresh the table and try again."))
        }

        guard current.uid == getuid() else {
            return .failure(ActionError("Not permitted — that process belongs to another user."))
        }

        if !force,
           let application = NSRunningApplication(processIdentifier: pid),
           application.activationPolicy != .prohibited {
            // Recheck after the AppKit lookup. terminate() otherwise trusts
            // whatever now owns this PID if the first snapshot is stale.
            guard application.processIdentifier == pid,
                  let current = processSnapshot(for: pid),
                  current.startTime == expectedStartTime,
                  current.uid == process.uid
            else {
                return .failure(ActionError("That process changed or already exited. Refresh the table and try again."))
            }
            // A graphical application gets the same save-and-quit request as
            // clicking Quit in its own UI. Fall back to SIGTERM for apps that
            // reject the request or for processes without an app object.
            if application.terminate() { return .success(()) }
        }

        // Re-check after the AppKit lookup/termination attempt before sending
        // a signal. This narrows the PID-reuse race as much as kill(2) allows.
        guard let current = processSnapshot(for: pid),
              current.startTime == expectedStartTime,
              current.uid == process.uid
        else {
            return .failure(ActionError("That process changed or already exited. Refresh the table and try again."))
        }

        return send(force ? SIGKILL : SIGTERM, to: pid)
    }

    private static func send(_ signal: Int32, to pid: Int32) -> Result<Void, ActionError> {
        guard kill(pid, signal) != -1 else {
            let errorNumber = errno
            switch errorNumber {
            case EPERM:
                return .failure(ActionError("Not permitted — that process belongs to another user."))
            case ESRCH:
                return .failure(ActionError("That process already exited."))
            default:
                return .failure(ActionError("Couldn't quit the process (errno \(errorNumber))."))
            }
        }
        return .success(())
    }

    private struct ProcessSnapshot {
        let uid: uid_t
        let startTime: UInt64
    }

    private static func processSnapshot(for pid: Int32) -> ProcessSnapshot? {
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expectedSize) == expectedSize else {
            return nil
        }

        return ProcessSnapshot(
            uid: info.pbi_uid,
            startTime: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
        )
    }
}
