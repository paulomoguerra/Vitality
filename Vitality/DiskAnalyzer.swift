import AppKit
import Foundation

struct DiskEntry: Identifiable, Hashable {
    let name: String
    let path: String
    let size: Int64
    let isDirectory: Bool
    let modified: Date?

    var id: String { path }

    // Table sorting needs a Comparable key path, and Bool isn't.
    var sortKind: Int { isDirectory ? 0 : 1 }
}

/// The only success value a destructive file operation may return. Finder's
/// Trash can rename a conflicting item, so the destination is not necessarily
/// the source's filename and must be carried back to the UI.
struct TrashReceipt: Hashable {
    let sourceURL: URL
    let destinationURL: URL
}

/// Shared, testable boundary around `FileManager.trashItem`.
enum TrashMover {

    /// Verifies the URL returned by `FileManager` before callers update their
    /// list. Keeping this pure makes the dangerous edge easy to test without
    /// moving fixtures into a real user's Trash.
    static func verifyDestination(
        source: URL,
        resultingURL: URL?,
        fileExists: (URL) -> Bool
    ) -> Result<TrashReceipt, ActionError> {
        guard let resultingURL else {
            if !fileExists(source) {
                return .failure(ActionError(
                    "\(source.lastPathComponent) was removed permanently — this volume has no Trash. Vitality cannot put it back."
                ))
            }
            return .failure(ActionError(
                "Vitality moved the item but couldn't confirm its Trash destination. Open Trash to check before trying again."
            ))
        }
        guard fileExists(resultingURL) else {
            return .failure(ActionError(
                "Vitality couldn't verify that the item exists in Trash. Open Trash to check whether it was moved before trying again."
            ))
        }
        return .success(TrashReceipt(sourceURL: source, destinationURL: resultingURL))
    }

    /// Moves an item to Trash and requires a concrete, existing resulting URL.
    static func move(_ source: URL, fileManager: FileManager = .default)
    -> Result<TrashReceipt, ActionError> {
        var resultingURL: NSURL?
        do {
            try fileManager.trashItem(at: source, resultingItemURL: &resultingURL)
        } catch {
            return .failure(ActionError(
                "Couldn't move \(source.lastPathComponent) to the Trash: \(error.localizedDescription)"
            ))
        }

        return verifyDestination(
            source: source,
            resultingURL: resultingURL.map { $0 as URL },
            fileExists: { fileManager.fileExists(atPath: $0.path) }
        )
    }
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
        guard !Task.isCancelled else {
            return .failure(ActionError("Scan cancelled."))
        }
        let root = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .failure(ActionError("That folder doesn't exist. Choose another folder and scan again."))
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            return .failure(ActionError("Vitality doesn't have permission to read this folder."))
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey,
                                      .contentModificationDateKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let listed: [URL]
        do {
            listed = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
            )
        } catch {
            return .failure(ActionError(error.localizedDescription))
        }

        // Free up refuses com.apple.* under Caches; this browser must not
        // offer them as Trash rows if the user still opens that folder.
        let isCachesFolder = root.path.hasSuffix("/Library/Caches")
        let children = listed.filter { url in
            !(isCachesFolder && url.lastPathComponent.hasPrefix("com.apple."))
        }

        // Each iteration writes only its own slot, so no lock is needed.
        var results = [DiskEntry?](repeating: nil, count: children.count)
        results.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: children.count) { index in
                guard !Task.isCancelled else { return }
                let url = children[index]
                let values = try? url.resourceValues(forKeys: Set(keys))
                let isLink = values?.isSymbolicLink == true
                let isDir = !isLink && (values?.isDirectory ?? false)
                buffer[index] = DiskEntry(
                    name: url.lastPathComponent,
                    path: url.path,
                    size: isDir ? directorySize(url) : fileSize(values),
                    isDirectory: isDir,
                    modified: values?.contentModificationDate
                )
            }
        }

        guard !Task.isCancelled else {
            return .failure(ActionError("Scan cancelled."))
        }

        return .success(results.compactMap { $0 }.sorted { $0.size > $1.size })
    }

    private static func fileSize(_ values: URLResourceValues?) -> Int64 {
        Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }

    /// Iterative rather than recursive: deeply nested trees (node_modules being
    /// the obvious one) would otherwise risk blowing the stack.
    private static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            // Treat packages as ordinary directories so .app, .bundle, and
            // .xcodeproj contents contribute to the enclosing entry's size.
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? child.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true {
                total += fileSize(values)
                enumerator.skipDescendants()
                continue
            }
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
    static func moveToTrash(_ path: String) -> Result<TrashReceipt, ActionError> {
        TrashMover.move(URL(fileURLWithPath: path))
    }

    static func openTrash() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash"))
    }
}
