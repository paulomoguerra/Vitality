import XCTest

/// The cleanup scanner builds a list of things a user is invited to delete in
/// one click, so the tests that matter are the exclusions: the Apple caches it
/// must not offer, the recent download it must not call stale, the Trash it must
/// hand back with no URLs attached.
///
/// Every test drives `scanRoots` against a temporary tree rather than the real
/// home folder — the scanner's whole job is deciding what to remove, and a test
/// that pointed it at `~` would be deciding that about the developer's Mac.
final class CleanupScannerTests: XCTestCase {

    private var root: URL!
    private var derivedData: URL!
    private var caches: URL!
    private var trash: URL!
    private var downloads: URL!

    /// Fixed so the age fixtures are arithmetic, not a race with the clock.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitalityCleanupTests-\(UUID().uuidString)")
        derivedData = root.appendingPathComponent("DerivedData")
        caches = root.appendingPathComponent("Caches")
        trash = root.appendingPathComponent("Trash")
        downloads = root.appendingPathComponent("Downloads")
        for directory in [derivedData, caches, trash, downloads] {
            try FileManager.default.createDirectory(at: XCTUnwrap(directory),
                                                    withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    /// Writes `bytes` of filler, optionally backdating both timestamps.
    @discardableResult
    private func write(_ name: String, in directory: URL, bytes: Int = 4_096,
                       age: TimeInterval? = nil) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data([UInt8](repeating: 0x2A, count: bytes)).write(to: url)
        if let age {
            let date = now.addingTimeInterval(-age)
            try FileManager.default.setAttributes(
                [.modificationDate: date, .creationDate: date], ofItemAtPath: url.path
            )
        }
        return url
    }

    @discardableResult
    private func makeDirectory(_ name: String, in parent: URL) throws -> URL {
        let url = parent.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func scan() -> [CleanupCategory] {
        CleanupScanner.scanRoots(derivedData: derivedData, caches: caches,
                                 trash: trash, downloads: downloads, now: now)
    }

    private func category(_ id: String) -> CleanupCategory? {
        scan().first { $0.id == id }
    }

    /// The last path component of everything a category would trash.
    private func trashedNames(_ category: CleanupCategory) -> Set<String> {
        Set(category.urls.map(\.lastPathComponent))
    }

    // MARK: - isStale

    func testFileOlderThanNinetyDaysOnBothDatesIsStale() {
        let old = now.addingTimeInterval(-120 * day)
        XCTAssertTrue(CleanupScanner.isStale(old, old, now: now))
    }

    func testRecentFileIsNotStale() {
        let recent = now.addingTimeInterval(-3 * day)
        XCTAssertFalse(CleanupScanner.isStale(recent, recent, now: now))
    }

    /// The file was downloaded long ago but edited yesterday — plainly still in
    /// use, however old its creation date says it is.
    func testRecentlyModifiedFileIsNotStale() {
        XCTAssertFalse(CleanupScanner.isStale(now.addingTimeInterval(-1 * day),
                                              now.addingTimeInterval(-400 * day),
                                              now: now))
    }

    /// The mirror case: an old original saved to disk this morning. Its
    /// modification date is inherited and lies about how long it's been here.
    func testRecentlyCreatedFileIsNotStale() {
        XCTAssertFalse(CleanupScanner.isStale(now.addingTimeInterval(-400 * day),
                                              now.addingTimeInterval(-1 * day),
                                              now: now))
    }

    func testMissingDatesAreNotStale() {
        let old = now.addingTimeInterval(-400 * day)
        XCTAssertFalse(CleanupScanner.isStale(nil, old, now: now))
        XCTAssertFalse(CleanupScanner.isStale(old, nil, now: now))
        XCTAssertFalse(CleanupScanner.isStale(nil, nil, now: now))
    }

    /// Exactly ninety days old is inside the window, not outside it. The
    /// boundary belongs to the user.
    func testFileExactlyAtTheCutoffIsNotStale() {
        let cutoff = now.addingTimeInterval(-90 * day)
        XCTAssertFalse(CleanupScanner.isStale(cutoff, cutoff, now: now))
        XCTAssertTrue(CleanupScanner.isStale(cutoff.addingTimeInterval(-1),
                                             cutoff.addingTimeInterval(-1), now: now))
    }

    // MARK: - Caches

    /// The safety rule the whole category depends on: Apple's caches are live
    /// system state, and trashing them is how a cleaner breaks a Mac.
    func testExcludesAppleCaches() throws {
        try write("cache.bin", in: try makeDirectory("com.apple.Safari", in: caches))
        try write("cache.bin", in: try makeDirectory("com.apple.dt.Xcode", in: caches))
        try write("cache.bin", in: try makeDirectory("com.example.App", in: caches))

        let caches = try XCTUnwrap(category("caches"))

        XCTAssertEqual(trashedNames(caches), ["com.example.App"])
        XCTAssertEqual(caches.itemCount, 1)
    }

    /// A folder that only *contains* Apple caches has nothing to offer, and an
    /// empty row is worse than no row.
    func testOmitsCachesEntirelyWhenOnlyAppleCachesExist() throws {
        try write("cache.bin", in: try makeDirectory("com.apple.Safari", in: caches))

        XCTAssertNil(category("caches"))
    }

    func testCacheBytesCoverNestedContents() throws {
        let nested = try makeDirectory("com.example.App/Data/deeper", in: caches)
        try write("a.bin", in: nested, bytes: 8_192)
        try write("b.bin", in: nested, bytes: 8_192)

        let caches = try XCTUnwrap(category("caches"))

        XCTAssertGreaterThanOrEqual(caches.bytes, 16_384,
                                    "sizing must recurse, not stop at the top level")
    }

    // MARK: - DerivedData

    func testDerivedDataListsEachTopLevelChild() throws {
        try write("build.o", in: try makeDirectory("Vitality-abc123", in: derivedData))
        try write("build.o", in: try makeDirectory("Other-def456", in: derivedData))

        let derived = try XCTUnwrap(category("derived-data"))

        XCTAssertEqual(trashedNames(derived), ["Vitality-abc123", "Other-def456"])
        XCTAssertEqual(derived.itemCount, 2)
        XCTAssertEqual(derived.kind, .trashable)
    }

    /// No Xcode on the machine is the common case, not a failure.
    func testOmitsDerivedDataWhenTheFolderIsMissing() throws {
        try FileManager.default.removeItem(at: derivedData)
        try write("something.bin", in: downloads, age: 400 * day)

        XCTAssertNil(category("derived-data"))
        XCTAssertNotNil(category("old-downloads"), "one missing root must not sink the scan")
    }

    // MARK: - Trash

    /// The Trash is the undo buffer for everything else Vitality does, so it is
    /// reported and never acted on. Handing back URLs would invite the caller to
    /// empty it.
    func testTrashIsReportedWithNoURLsToDelete() throws {
        try write("discarded.bin", in: trash, bytes: 2_048)

        let bin = try XCTUnwrap(category("trash"))

        XCTAssertEqual(bin.kind, .trashBin)
        XCTAssertTrue(bin.urls.isEmpty)
        XCTAssertEqual(bin.itemCount, 1)
        XCTAssertGreaterThan(bin.bytes, 0)
    }

    func testOmitsEmptyTrash() {
        XCTAssertNil(category("trash"))
    }

    // MARK: - Old downloads

    func testListsOnlyDownloadsOlderThanNinetyDays() throws {
        try write("ancient.dmg", in: downloads, age: 200 * day)
        try write("stale.zip", in: downloads, age: 91 * day)
        try write("yesterday.pdf", in: downloads, age: 1 * day)

        let old = try XCTUnwrap(category("old-downloads"))

        XCTAssertEqual(trashedNames(old), ["ancient.dmg", "stale.zip"])
    }

    /// A folder in Downloads is usually a working directory, and its own
    /// timestamps say nothing about the files inside it.
    func testIgnoresFoldersInDownloads() throws {
        let project = try makeDirectory("old-project", in: downloads)
        try write("file.txt", in: project)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-400 * day),
             .creationDate: now.addingTimeInterval(-400 * day)],
            ofItemAtPath: project.path
        )

        XCTAssertNil(category("old-downloads"), "folders are never offered")
    }

    /// Top level only — a stale file buried in a folder the user still works in
    /// is not the scanner's to take.
    func testDoesNotRecurseIntoDownloadSubfolders() throws {
        let nested = try makeDirectory("archive", in: downloads)
        try write("buried.zip", in: nested, age: 400 * day)
        try write("visible.zip", in: downloads, age: 400 * day)

        let old = try XCTUnwrap(category("old-downloads"))

        XCTAssertEqual(trashedNames(old), ["visible.zip"])
    }

    // MARK: - Assembly

    func testOmitsCategoriesThatWouldFreeNothing() {
        XCTAssertTrue(scan().isEmpty, "empty roots produce no rows at all")
    }

    func testCleanWithNothingSelectedFreesNothing() {
        guard case .success(let bytes) = CleanupScanner.clean([]) else {
            return XCTFail("an empty selection is a successful no-op")
        }
        XCTAssertEqual(bytes, 0)
    }

    func testCategoriesAreOrderedBiggestFirst() throws {
        try write("small.o", in: try makeDirectory("Vitality-abc123", in: derivedData), bytes: 4_096)
        try write("big.bin", in: try makeDirectory("com.example.App", in: caches), bytes: 512_000)

        let ids = scan().map(\.id)

        XCTAssertEqual(ids, ["caches", "derived-data"])
    }

    // MARK: - Cleaning

    func testCleanMovesEveryURLAndReportsBytesFreed() throws {
        try write("build.o", in: try makeDirectory("Vitality-abc123", in: derivedData), bytes: 8_192)
        let derived = try XCTUnwrap(category("derived-data"))

        guard case .success(let bytes) = CleanupScanner.clean([derived]) else {
            return XCTFail("trashing a temporary folder should succeed")
        }

        XCTAssertEqual(bytes, derived.bytes)
        XCTAssertTrue(try FileManager.default
            .contentsOfDirectory(atPath: derivedData.path).isEmpty)

        // Trashed, not deleted — the point of the whole design.
        addTeardownBlock {
            let trashed = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".Trash/Vitality-abc123")
            try? FileManager.default.removeItem(at: trashed)
        }
    }

    /// The Trash category carries no URLs, so cleaning it must be a no-op rather
    /// than an error or, worse, an attempt.
    func testCleanSkipsTheTrashBin() throws {
        try write("discarded.bin", in: trash)
        let bin = try XCTUnwrap(category("trash"))

        guard case .success(let bytes) = CleanupScanner.clean([bin]) else {
            return XCTFail("the trash bin category is not an action")
        }

        XCTAssertEqual(bytes, 0)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: trash.appendingPathComponent("discarded.bin").path))
    }

    /// A URL that vanished between scan and click must not abort the rest: the
    /// user still gets the space from everything that did work.
    func testCleanAttemptsEveryURLAndReportsTheFirstFailure() throws {
        let survivor = try makeDirectory("Vitality-abc123", in: derivedData)
        try write("build.o", in: survivor)
        let ghost = derivedData.appendingPathComponent("Gone-999")

        let category = CleanupCategory(id: "derived-data", label: "Xcode DerivedData",
                                       icon: "hammer.fill", bytes: 0, itemCount: 2,
                                       kind: .trashable, urls: [ghost, survivor])

        guard case .failure(let error) = CleanupScanner.clean([category]) else {
            return XCTFail("a URL that can't be trashed is a failure")
        }

        XCTAssertTrue(error.message.hasPrefix("Moved 1 of 2 items"),
                      "the message has to admit the partial success: \(error.message)")
        XCTAssertTrue(error.message.contains("first error:"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: survivor.path),
                       "the good item is trashed even though the run reports failure")

        addTeardownBlock {
            let trashed = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".Trash/Vitality-abc123")
            try? FileManager.default.removeItem(at: trashed)
        }
    }

    func testCleanSkipsAppleCacheFolders() throws {
        let apple = try makeDirectory("com.apple.Safari", in: caches)
        try write("cache.bin", in: apple)
        let category = CleanupCategory(
            id: "caches", label: "App caches", icon: "shippingbox.fill",
            bytes: 4_096, itemCount: 1, kind: .trashable, urls: [apple]
        )

        guard case .success(let bytes) = CleanupScanner.clean([category]) else {
            return XCTFail("skipping an Apple cache is a successful no-op")
        }
        XCTAssertEqual(bytes, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: apple.path))
    }

    func testCleanSkipsADownloadThatIsNoLongerStale() throws {
        let file = try write("old.pdf", in: downloads, bytes: 8_192, age: 120 * day)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(), .creationDate: Date()],
            ofItemAtPath: file.path
        )
        let category = CleanupCategory(
            id: "old-downloads", label: "Downloads older than 90 days",
            icon: "clock.arrow.circlepath", bytes: 8_192, itemCount: 1,
            kind: .trashable, urls: [file]
        )

        guard case .success(let bytes) = CleanupScanner.clean([category]) else {
            return XCTFail("a freshly touched download must be skipped, not failed")
        }
        XCTAssertEqual(bytes, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
