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

    /// How much of a file is enough to tell it apart from a same-sized
    /// neighbour. Two files that differ at all almost always differ inside the
    /// first block — headers, timestamps, magic numbers — so reading 64 KB
    /// answers "are these different?" for nearly every pair, and only genuine
    /// candidates go on to be read in full.
    private static let prefixSize = 64 * 1024

    /// A file that survived size grouping and is worth reading.
    private struct Candidate {
        let url: URL
        let size: Int64
        let modified: Date?
    }

    /// Size travels with the digest because two files of different lengths can
    /// share a prefix hash, and merging those would report them as identical.
    private struct DigestKey: Hashable {
        let size: Int64
        let digest: String
    }

    /// Finds exact duplicate files under a user-selected directory.
    ///
    /// Three sieves, each cheaper than the one after it: group by size (reads
    /// nothing), then by a 64 KB prefix digest, and only then hash the survivors
    /// end to end. A folder of ten same-sized videos that merely happen to match
    /// in length is settled after 640 KB instead of gigabytes. Both hashing
    /// passes run across all cores. Packages and hidden files are skipped.
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

        let keySet = Set(keys)
        var bySize: [Int64: [Candidate]] = [:]
        for case let url as URL in enumerator {
            // Read the resource values once, here. The modification date is
            // wanted later, and asking the filesystem for it a second time is
            // a stat per surviving file for something already in hand.
            guard let values = try? url.resourceValues(forKeys: keySet),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize > 0 else { continue }
            bySize[Int64(fileSize), default: []].append(Candidate(
                url: url,
                size: Int64(fileSize),
                modified: values.contentModificationDate
            ))
        }

        // Sieve two: a 64 KB prefix. For anything at or under that size the
        // prefix *is* the whole file, so those are settled here and never read
        // again.
        var byDigest: [DigestKey: [DuplicateFile]] = [:]
        var contested: [[Candidate]] = []
        for (size, candidates) in bySize where candidates.count > 1 {
            let prefixes = digests(of: candidates, upTo: prefixSize)
            var byPrefix: [String: [Candidate]] = [:]
            for (candidate, prefix) in zip(candidates, prefixes) {
                guard let prefix else { continue }
                byPrefix[prefix, default: []].append(candidate)
            }
            for (prefix, matches) in byPrefix where matches.count > 1 {
                if size <= Int64(prefixSize) {
                    byDigest[DigestKey(size: size, digest: prefix)] = matches.map(Self.file(from:))
                } else {
                    contested.append(matches)
                }
            }
        }

        // Sieve three: the full read, for the few that got this far.
        for candidates in contested {
            let full = digests(of: candidates, upTo: nil)
            for (candidate, digest) in zip(candidates, full) {
                guard let digest else { continue }
                byDigest[DigestKey(size: candidate.size, digest: digest), default: []]
                    .append(Self.file(from: candidate))
            }
        }

        let groups = byDigest.map { key, files in
            DuplicateGroup(
                digest: key.digest,
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

    private static func file(from candidate: Candidate) -> DuplicateFile {
        DuplicateFile(path: candidate.url.path,
                      name: candidate.url.lastPathComponent,
                      size: candidate.size,
                      modified: candidate.modified)
    }

    /// Hashes a batch across every core. Hashing is CPU-bound on top of I/O the
    /// kernel can overlap, so one file at a time leaves most of the machine
    /// idle during exactly the operation the user is waiting on.
    ///
    /// Each iteration writes its own slot and reads no other, so the results
    /// need no lock.
    private static func digests(of candidates: [Candidate], upTo limit: Int?) -> [String?] {
        var results = [String?](repeating: nil, count: candidates.count)
        results.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
                buffer[index] = hash(candidates[index].url, upTo: limit)
            }
        }
        return results
    }

    /// `limit` reads at most that many bytes; `nil` reads the whole file.
    private static func hash(_ url: URL, upTo limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        var remaining = limit ?? Int.max
        do {
            while remaining > 0 {
                let data = try handle.read(upToCount: min(chunkSize, remaining)) ?? Data()
                if data.isEmpty { break }
                hasher.update(data: data)
                remaining -= data.count
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }
}
