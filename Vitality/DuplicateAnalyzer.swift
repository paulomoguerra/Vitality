import CryptoKit
import Foundation

struct DuplicateFile: Identifiable, Hashable {
    let path: String
    let name: String
    let size: Int64
    let modified: Date?

    var id: String { path }
}

struct DuplicateGroup: Identifiable, Hashable {
    let digest: String
    let files: [DuplicateFile]

    var id: String { "\(digest)-\(files.first?.size ?? 0)" }
    var size: Int64 { files.first?.size ?? 0 }
    var reclaimable: Int64 { size * Int64(max(0, files.count - 1)) }
}

enum DuplicateAnalyzer {

    private static let chunkSize = 1024 * 1024

    /// Finds exact duplicate files under a user-selected directory.
    /// Files are grouped by logical size before hashing, so most files are
    /// never read. Packages and hidden files are skipped by default.
    static func scan(path: String) -> Result<[DuplicateGroup], ActionError> {
        let root = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .failure(ActionError("That folder doesn't exist."))
        }
        guard FileManager.default.isReadableFile(atPath: root.path) else {
            return .failure(ActionError("Vitality doesn't have permission to read this folder."))
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return .failure(ActionError("Vitality couldn't scan that folder."))
        }

        var bySize: [Int64: [URL]] = [:]
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize > 0 else { continue }
            bySize[Int64(fileSize), default: []].append(url)
        }

        var byDigest: [String: [DuplicateFile]] = [:]
        for (size, urls) in bySize where urls.count > 1 {
            for url in urls {
                guard let digest = hash(url) else { continue }
                let values = try? url.resourceValues(forKeys: Set(keys))
                byDigest[digest, default: []].append(DuplicateFile(
                    path: url.path,
                    name: url.lastPathComponent,
                    size: size,
                    modified: values?.contentModificationDate
                ))
            }
        }

        let groups = byDigest.map { digest, files in
            DuplicateGroup(
                digest: digest,
                files: files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            )
        }
        .filter { $0.files.count > 1 }
        .sorted {
            if $0.reclaimable != $1.reclaimable { return $0.reclaimable > $1.reclaimable }
            return ($0.files.first?.name ?? "").localizedStandardCompare($1.files.first?.name ?? "") == .orderedAscending
        }

        return .success(groups)
    }

    @discardableResult
    static func moveToTrash(_ file: DuplicateFile) -> Result<Void, ActionError> {
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: file.path), resultingItemURL: nil)
            return .success(())
        } catch {
            return .failure(ActionError("Couldn't move \(file.name) to the Trash: \(error.localizedDescription)"))
        }
    }

    @discardableResult
    static func move(_ file: DuplicateFile, to folder: URL) -> Result<URL, ActionError> {
        let source = URL(fileURLWithPath: file.path).standardizedFileURL
        let destinationFolder = folder.standardizedFileURL
        var destination = destinationFolder.appendingPathComponent(file.name)

        guard source != destination.standardizedFileURL else {
            return .failure(ActionError("That file is already in the selected folder."))
        }

        var attempt = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let stem = destination.deletingPathExtension().lastPathComponent
            let ext = destination.pathExtension
            let name = ext.isEmpty ? "\(stem) \(attempt)" : "\(stem) \(attempt).\(ext)"
            destination = destinationFolder.appendingPathComponent(name)
            attempt += 1
        }

        do {
            try FileManager.default.moveItem(at: source, to: destination)
            return .success(destination)
        } catch {
            return .failure(ActionError("Couldn't move \(file.name): \(error.localizedDescription)"))
        }
    }

    private static func hash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        do {
            while true {
                let data = try handle.read(upToCount: chunkSize) ?? Data()
                if data.isEmpty { break }
                hasher.update(data: data)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }
}
