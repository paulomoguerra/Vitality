import XCTest

/// `analyze` is the folder browser's only input. The cases that matter are
/// the ones that would show the wrong size, or treat a missing path as an
/// empty folder and invite the user to drill into nothing.
final class DiskAnalyzerTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitalityDiskTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func write(_ name: String, bytes: Int) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data([UInt8](repeating: 0x61, count: bytes)).write(to: url)
        return url
    }

    private func analyze() throws -> [DiskEntry] {
        switch DiskAnalyzer.analyze(path: root.path) {
        case .success(let entries): return entries
        case .failure(let error):   throw error
        }
    }

    func testMissingFolderIsAnErrorNotAnEmptyListing() {
        let missing = root.appendingPathComponent("not-here").path

        guard case .failure = DiskAnalyzer.analyze(path: missing) else {
            return XCTFail("a folder that doesn't exist is an error, not zero files")
        }
    }

    func testAFileIsNotAFolder() throws {
        let file = try write("readme.txt", bytes: 32)

        guard case .failure = DiskAnalyzer.analyze(path: file.path) else {
            return XCTFail("pointing the scanner at a file has to fail, not list it")
        }
    }

    func testEmptyFolderSucceedsWithNoEntries() throws {
        XCTAssertTrue(try analyze().isEmpty)
    }

    func testEntriesAreSortedLargestFirst() throws {
        try write("small.bin", bytes: 4_096)
        try write("large.bin", bytes: 256_000)

        let names = try analyze().map(\.name)

        XCTAssertEqual(names.first, "large.bin")
        XCTAssertEqual(Set(names), ["small.bin", "large.bin"])
    }

    func testDirectorySizeIncludesNestedFiles() throws {
        let nested = root.appendingPathComponent("folder/deeper")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data([UInt8](repeating: 0x62, count: 128_000))
            .write(to: nested.appendingPathComponent("buried.bin"))
        try write("sidecar.bin", bytes: 4_096)

        let entries = try analyze()
        let folder = try XCTUnwrap(entries.first { $0.name == "folder" })
        let sidecar = try XCTUnwrap(entries.first { $0.name == "sidecar.bin" })

        XCTAssertTrue(folder.isDirectory)
        XCTAssertGreaterThan(folder.size, sidecar.size)
    }

    func testSortKindPutsDirectoriesBeforeFiles() {
        let directory = DiskEntry(name: "A", path: "/A", size: 1, isDirectory: true, modified: nil)
        let file = DiskEntry(name: "B", path: "/B", size: 1, isDirectory: false, modified: nil)

        XCTAssertEqual(directory.sortKind, 0)
        XCTAssertEqual(file.sortKind, 1)
        XCTAssertLessThan(directory.sortKind, file.sortKind)
    }

    func testSuggestedRootsDoNotIncludeCaches() {
        XCTAssertFalse(DiskAnalyzer.suggestedRoots.contains { $0.label == "Caches" })
    }

    func testAnalyzeSkipsHiddenFiles() throws {
        try write(".secret.bin", bytes: 64_000)
        try write("visible.bin", bytes: 4_096)

        XCTAssertEqual(try analyze().map(\.name), ["visible.bin"])
    }

    /// A symlink must not be sized as its target. Trashing the row moves the
    /// link, not the 40 GB folder it points at.
    func testSymlinkIsNotSizedAsItsTarget() throws {
        let target = try write("target.bin", bytes: 200_000)
        let link = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let alias = try XCTUnwrap(try analyze().first { $0.name == "alias" })

        XCTAssertFalse(alias.isDirectory)
        XCTAssertLessThan(alias.size, 200_000)
    }

    func testCachesListingOmitsAppleFolders() throws {
        let caches = root.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: caches.appendingPathComponent("com.apple.Safari"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: caches.appendingPathComponent("com.example.App"),
            withIntermediateDirectories: true
        )

        switch DiskAnalyzer.analyze(path: caches.path) {
        case .success(let entries):
            XCTAssertEqual(Set(entries.map(\.name)), ["com.example.App"])
        case .failure(let error):
            throw error
        }
    }
}
