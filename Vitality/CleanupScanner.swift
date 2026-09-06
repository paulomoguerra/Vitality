import Foundation

/// One bucket of reclaimable space, already sized and already resolved to the
/// exact URLs that would be trashed. The UI shows the total; `urls` is what the
/// user is actually agreeing to when they hit the button.
struct CleanupCategory: Identifiable, Hashable {
    enum Kind: Hashable {
        /// Items Vitality can move to the Trash itself.
        case trashable
        /// The Trash itself — Vitality only reports its size and opens it;
        /// emptying is Finder's job.
        case trashBin
    }

    let id: String
    let label: String
    let icon: String
    let bytes: Int64
    let itemCount: Int
    let kind: Kind
    /// The concrete file URLs that would be trashed (empty for `.trashBin`).
    let urls: [URL]

    /// Caches and DerivedData come back. Old downloads do not.
    var isRebuildable: Bool { kind == .trashable && id != "old-downloads" }
}

/// Finds disk space that is safe to give back.
///
/// "Safe" is doing real work in that sentence, and it's the reason this scanner
/// looks at four narrow places rather than hunting the whole home folder:
///
/// - **DerivedData** and **app caches** are, by contract, rebuildable. Deleting
///   them costs a slow first launch, never data.
/// - **`com.apple.*` caches are excluded** even though they're the biggest
///   names in `~/Library/Caches`. Parts of the system treat those directories as
///   live state rather than a cache — pulling them out from under a running
///   daemon produces the class of bug that looks like a broken Mac and gets
///   blamed on everything except the cleaner that caused it. The few gigabytes
///   aren't worth it.
/// - **The Trash is reported, not emptied.** It is the undo buffer for every
///   other destructive thing Vitality does; a cleaner that empties it removes
///   the user's last way back. Vitality shows the number and opens the folder.
/// - **Old downloads** are the one category holding original data, so the bar is
///   higher — see `isStale`.
///
/// Everything Vitality removes goes to the Trash, never `unlink`, so even a
/// wrong call here is recoverable.
enum CleanupScanner {

    /// A download has to be untouched for a full quarter before Vitality will
    /// suggest it. Shorter windows catch things people are still using.
    private static let staleDownloadAge: TimeInterval = 90 * 24 * 60 * 60

    /// Resource keys needed to judge a download; fetched once with the listing
    /// so deciding costs no extra `stat` per file.
    private static let downloadKeys: [URLResourceKey] = [
        .isRegularFileKey, .contentModificationDateKey, .creationDateKey,
    ]

    /// Keys for measuring. `totalFileAllocatedSize` is what the file costs the
    /// volume, which is the number a user reclaims — logical size overstates
    /// sparse files and understates block padding.
    private static let sizeKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// Walks the four categories and sizes them. Slow — call off the main thread.
    static func scan() -> [CleanupCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return scanRoots(
            derivedData: home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            caches: home.appendingPathComponent("Library/Caches"),
            trash: home.appendingPathComponent(".Trash"),
            downloads: home.appendingPathComponent("Downloads"),
            now: Date()
        )
    }

    /// The real work, with the four roots injected so it can be pointed at a
    /// fixture instead of the user's home folder.
    ///
    /// Categories that would free nothing are dropped rather than shown as a
    /// zero — a row offering 0 bytes is a row the user has to read and dismiss.
    /// The rest are ordered biggest first, since that is the order they'd be
    /// acted on in.
    static func scanRoots(derivedData: URL, caches: URL, trash: URL,
                          downloads: URL, now: Date) -> [CleanupCategory] {
        var categories = [
            trashable(id: "derived-data",
                      label: "Xcode DerivedData",
                      icon: "hammer.fill",
                      urls: children(of: derivedData)),
            trashable(id: "caches",
                      label: "App caches",
                      icon: "shippingbox.fill",
                      urls: reclaimableCaches(in: caches)),
            trashBin(at: trash),
            trashable(id: "old-downloads",
                      label: "Downloads older than 90 days",
                      icon: "clock.arrow.circlepath",
                      urls: staleDownloads(in: downloads, now: now)),
        ].compactMap { $0 }

        categories.sort { $0.bytes > $1.bytes }
        return categories
    }

    /// Moves every URL of the given categories to the Trash. Returns bytes
    /// reclaimed; partial failures are collected, first message reported.
    ///
    /// One failure doesn't abort the run: a single locked file shouldn't cost
    /// the user the other forty gigabytes they asked for. Sizes are re-measured
    /// here rather than taken from the scan, because a scan the user has been
    /// staring at for a minute is already out of date.
    static func clean(_ categories: [CleanupCategory]) -> Result<Int64, ActionError> {
        var reclaimed: Int64 = 0
        var attempted = 0
        var moved = 0
        var firstError: String?

        for category in categories where category.kind == .trashable {
            for url in category.urls {
                if url.lastPathComponent.hasPrefix("com.apple.") { continue }
                if category.id == "old-downloads" {
                    let values = try? url.resourceValues(forKeys: [
                        .contentModificationDateKey, .creationDateKey,
                    ])
                    guard isStale(values?.contentModificationDate,
                                  values?.creationDate, now: Date()) else { continue }
                }
                attempted += 1
                let size = allocatedSize(url)
                switch TrashMover.move(url) {
                case .success:
                    reclaimed += size
                    moved += 1
                case .failure(let error):
                    if firstError == nil { firstError = error.message }
                }
            }
        }

        if let firstError {
            return .failure(ActionError(
                "Moved \(moved) of \(attempted) items to the Trash; first error: \(firstError)"
            ))
        }
        return .success(reclaimed)
    }

    /// Whether a download is old enough to offer up.
    ///
    /// *Both* dates have to be old. A file downloaded last week onto an old
    /// original keeps a stale modification date, and a file created long ago but
    /// edited yesterday is plainly still in use — either one alone would put
    /// something the user still wants on the list. A missing date is treated as
    /// "not stale": Vitality doesn't propose deleting things it can't date.
    static func isStale(_ modified: Date?, _ created: Date?, now: Date) -> Bool {
        guard let modified, let created else { return false }
        let cutoff = now.addingTimeInterval(-staleDownloadAge)
        return modified < cutoff && created < cutoff
    }

    // MARK: - Categories

    private static func trashable(id: String, label: String, icon: String,
                                  urls: [URL]) -> CleanupCategory? {
        let bytes = sizes(of: urls).reduce(0, +)
        guard bytes > 0 else { return nil }
        return CleanupCategory(id: id, label: label, icon: icon, bytes: bytes,
                               itemCount: urls.count, kind: .trashable, urls: urls)
    }

    private static func trashBin(at trash: URL) -> CleanupCategory? {
        let items = children(of: trash)
        let bytes = sizes(of: items).reduce(0, +)
        guard bytes > 0 else { return nil }
        // No URLs: this category is a report and a shortcut to Finder, never an
        // action. See the type comment for why emptying isn't Vitality's job.
        return CleanupCategory(id: "trash", label: "Trash", icon: "trash.fill",
                               bytes: bytes, itemCount: items.count,
                               kind: .trashBin, urls: [])
    }

    /// Everything directly under `~/Library/Caches` except Apple's own.
    private static func reclaimableCaches(in caches: URL) -> [URL] {
        children(of: caches).filter { !$0.lastPathComponent.hasPrefix("com.apple.") }
    }

    /// Top level only, and regular files only. A folder in Downloads is usually
    /// an unpacked project someone is working in, and its own timestamps say
    /// nothing about the files inside it — the recursive version of this check
    /// is how a cleaner eats a working directory.
    private static func staleDownloads(in downloads: URL, now: Date) -> [URL] {
        children(of: downloads, keys: downloadKeys).filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(downloadKeys)),
                  values.isRegularFile == true else { return false }
            return isStale(values.contentModificationDate, values.creationDate, now: now)
        }
    }

    // MARK: - Measuring

    /// A directory that doesn't exist — no Xcode installed, no Downloads folder
    /// — is simply nothing to clean, not an error worth surfacing.
    private static func children(of directory: URL, keys: [URLResourceKey] = []) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: []
        )) ?? []
    }

    /// Sizes a batch across every core. One DerivedData subtree can hold
    /// hundreds of thousands of files, so measuring them one after another
    /// leaves the machine idle during exactly the wait the user is watching.
    ///
    /// Each iteration writes its own slot and reads no other, so no lock.
    private static func sizes(of urls: [URL]) -> [Int64] {
        var results = [Int64](repeating: 0, count: urls.count)
        results.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: urls.count) { index in
                buffer[index] = allocatedSize(urls[index])
            }
        }
        return results
    }

    /// Total allocated bytes of a file or, recursively, of a directory.
    ///
    /// Iterative rather than recursive: cache folders nest arbitrarily deep
    /// (npm and SwiftPM checkouts being the usual offenders) and a recursive
    /// walk risks the stack.
    private static func allocatedSize(_ url: URL) -> Int64 {
        let keySet = Set(sizeKeys)
        let values = try? url.resourceValues(forKeys: keySet)
        if values?.isSymbolicLink == true { return fileSize(values) }
        guard values?.isDirectory == true else { return fileSize(values) }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: sizeKeys,
            // Packages are ordinary directories here: an .app or .xcodeproj
            // inside a cache still occupies its contents' worth of disk.
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let childValues = try? child.resourceValues(forKeys: keySet) else { continue }
            if childValues.isSymbolicLink == true {
                total += fileSize(childValues)
                enumerator.skipDescendants()
                continue
            }
            if childValues.isDirectory == true { continue }
            total += fileSize(childValues)
        }
        return total
    }

    private static func fileSize(_ values: URLResourceValues?) -> Int64 {
        Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }
}
