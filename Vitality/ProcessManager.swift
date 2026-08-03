import Foundation

struct RunningProcess: Identifiable, Hashable {
    let pid: Int32
    let uid: uid_t
    let cpu: Double
    let memoryBytes: Int64
    let name: String

    var id: Int32 { pid }

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
    static func list(limit: Int = 60) -> [RunningProcess] {
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
                cpu: cpu,
                memoryBytes: rssKB * 1024,   // ps reports RSS in kilobytes
                name: parts[4]
            ))
            if result.count >= limit { break }
        }
        return result
    }

    /// Asks a process to quit. `force` escalates to SIGKILL, which gives the
    /// app no chance to save state — so the UI keeps that behind a separate,
    /// explicit choice rather than making it the default.
    @discardableResult
    static func terminate(pid: Int32, force: Bool = false) -> Result<Void, ActionError> {
        guard pid > 0 else { return .failure(ActionError("Invalid process ID.")) }
        if pid == getpid() { return .failure(ActionError("Vitality can't quit itself.")) }

        let result = kill(pid, force ? SIGKILL : SIGTERM)
        if result == 0 { return .success(()) }

        switch errno {
        case EPERM:
            return .failure(ActionError("Not permitted — that process belongs to another user."))
        case ESRCH:
            return .failure(ActionError("That process already exited."))
        default:
            return .failure(ActionError("Couldn't quit the process (errno \(errno))."))
        }
    }
}
