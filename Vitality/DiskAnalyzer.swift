import AppKit
import Foundation

struct DiskEntry: Codable, Identifiable, Hashable {
    let name: String?
    let path: String?
    let size: Int64?
    let isDir: Bool?
    let lastAccess: String?

    var id: String { path ?? name ?? UUID().uuidString }
    var displayName: String { name ?? (path as NSString?)?.lastPathComponent ?? "—" }

    enum CodingKeys: String, CodingKey {
        case name, path, size
        case isDir = "is_dir"
        case lastAccess = "last_access"
    }
}

struct DiskAnalysis: Codable {
    let path: String?
    let entries: [DiskEntry]?
}

enum DiskAnalyzer {

    /// Common places worth scanning. Analysing `/` walks the whole volume and
    /// takes minutes, so the UI offers these targeted starting points instead.
    static var suggestedRoots: [(label: String, path: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            ("Downloads", "\(home)/Downloads"),
            ("Desktop", "\(home)/Desktop"),
            ("Documents", "\(home)/Documents"),
            ("Caches", "\(home)/Library/Caches"),
            ("Application Support", "\(home)/Library/Application Support"),
            ("Home folder", home),
        ]
    }

    static func analyze(path: String) -> Result<DiskAnalysis, MoleError> {
        MoleCLI.decode(DiskAnalysis.self, from: ["analyze", "-json", path], timeout: 180)
    }

    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Moves to Trash rather than deleting. Vitality is pointing users at their
    /// biggest files, which is exactly the situation where a misread row costs
    /// something irreplaceable — Trash keeps that recoverable.
    static func moveToTrash(_ path: String) -> Result<Void, ActionError> {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return .success(())
        } catch {
            return .failure(ActionError(error.localizedDescription))
        }
    }

    static func trashSize() -> Int64 {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let trash = URL(fileURLWithPath: "\(home)/.Trash")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: trash, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isDirectoryKey]
        ) else { return 0 }

        return items.reduce(Int64(0)) { total, url in
            total + (directorySize(url))
        }
    }

    private static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }

        if values.isDirectory == true {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: keys
            ) else { return 0 }
            return children.reduce(Int64(0)) { $0 + directorySize($1) }
        }
        return Int64(values.totalFileAllocatedSize ?? 0)
    }

    static func emptyTrash() {
        // Deliberately hands off to Finder rather than deleting directly:
        // emptying the Trash is irreversible, so the confirmation should come
        // from the system UI the user already knows.
        let script = """
        tell application "Finder" to empty the trash
        """
        guard let appleScript = NSAppleScript(source: script) else { return }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }
}
