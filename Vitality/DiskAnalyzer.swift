import AppKit
import Foundation

struct DiskEntry: Identifiable, Hashable {
    let name: String
    let path: String
    let size: Int64
    let isDirectory: Bool
    let modified: Date?

    var id: String { path }

    // Table sorting needs Comparable key paths.
    var sortSize: Int64 { size }
    var sortName: String { name }
    var sortKind: Int { isDirectory ? 0 : 1 }
}

enum DiskAnalyzer {

    /// Common places worth scanning. Scanning a whole volume walks millions of
    /// files, so the UI offers targeted starting points instead.
    static var suggestedRoots: [(label: String, path: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            ("Downloads", "\(home)/Downloads"),
            ("Desktop", "\(home)/Desktop"),
            ("Documents", "\(home)/Documents"),
            ("Caches", "\(home)/Library/Caches"),
            ("Application Support", "\(home)/Library/Application Support"),
            ("Developer", "\(home)/Library/Developer"),
            ("Home folder", home),
        ]
    }

    /// Lists a folder's immediate children with their full recursive sizes.
    ///
    /// Sizes for each top-level child are computed in parallel — one slow
    /// subtree (a DerivedData folder, say) would otherwise stall the whole scan
    /// while the other cores sit idle.
    static func analyze(path: String) -> Result<[DiskEntry], ActionError> {
        let root = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .failure(ActionError("That folder doesn't exist."))
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            return .failure(ActionError("Vitality doesn't have permission to read this folder."))
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: keys, options: []
            )
        } catch {
            return .failure(ActionError(error.localizedDescription))
        }

        var results = [DiskEntry?](repeating: nil, count: children.count)
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: children.count) { index in
            let url = children[index]
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false
            let entry = DiskEntry(
                name: url.lastPathComponent,
                path: url.path,
                size: isDir ? directorySize(url) : fileSize(values),
                isDirectory: isDir,
                modified: values?.contentModificationDate
            )
            lock.lock(); results[index] = entry; lock.unlock()
        }

        return .success(results.compactMap { $0 }.sorted { $0.size > $1.size })
    }

    private static func fileSize(_ values: URLResourceValues?) -> Int64 {
        Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }

    /// Iterative rather than recursive: deeply nested trees (node_modules being
    /// the obvious one) would otherwise risk blowing the stack.
    private static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            // Bundles are shown as single items in Finder, so their innards
            // shouldn't be walked separately — but they must still be counted.
            options: [.skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true { continue }
            total += fileSize(values)
        }
        return total
    }

    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Moves to Trash rather than deleting. Vitality points users at their
    /// biggest files — exactly the situation where a misread row costs
    /// something irreplaceable.
    static func moveToTrash(_ path: String) -> Result<Void, ActionError> {
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            return .success(())
        } catch {
            return .failure(ActionError(error.localizedDescription))
        }
    }

    static func openTrash() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash"))
    }
}
