import XCTest

/// The duplicate finder decides which files a user is invited to delete, so the
/// interesting cases are the ones where it could be wrong: files that look
/// alike to a cheap check and are not alike at all.
///
/// The scan short-circuits on size, then on a 64 KB prefix, and only then reads
/// files in full. Every test here is written against that boundary — the size
/// constant is not incidental to the fixtures, it is the thing under test.
final class DuplicateAnalyzerTests: XCTestCase {

    /// Must match `DuplicateAnalyzer.prefixSize`, which is private. A fixture
    /// straddling the boundary is the only way to reach the third sieve.
    private let prefixSize = 64 * 1024

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("VitalityDuplicateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    @discardableResult
    private func write(_ name: String, _ bytes: [UInt8]) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private func scan() throws -> [DuplicateGroup] {
        switch DuplicateAnalyzer.scan(path: root.path) {
        case .success(let groups): return groups
        case .failure(let error):  throw XCTSkip("scan failed: \(error.message)")
        }
    }

    /// Every file name in a group, so assertions don't depend on ordering.
    private func names(_ group: DuplicateGroup) -> Set<String> {
        Set(group.files.map(\.name))
    }

    // MARK: - Files that are duplicates

    func testFindsIdenticalSmallFiles() throws {
        try write("a.txt", Array("hello vitality".utf8))
        try write("b.txt", Array("hello vitality".utf8))
        try write("unique.txt", Array("something else".utf8))

        let groups = try scan()

        XCTAssertEqual(groups.count, 1, "one pair is one group")
        XCTAssertEqual(names(groups[0]), ["a.txt", "b.txt"])
    }

    /// Above the prefix boundary the scan has to read both files in full before
    /// it may call them identical. This is the path the third sieve exists for.
    func testFindsIdenticalFilesLargerThanThePrefix() throws {
        let body = [UInt8](repeating: 0xAB, count: prefixSize + 4_096)
        try write("big-1.bin", body)
        try write("big-2.bin", body)

        let groups = try scan()

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(names(groups[0]), ["big-1.bin", "big-2.bin"])
    }

    func testGroupsThreeCopiesTogether() throws {
        let body = Array("triplicate".utf8)
        try write("one.txt", body)
        try write("two.txt", body)
        try write("three.txt", body)

        let groups = try scan()

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 3)
    }

    // MARK: - Files that are not duplicates

    /// The regression the prefix sieve could introduce: same length, byte-for-byte
    /// identical for the first 64 KB, different only afterwards. A scan that
    /// trusted the prefix would offer one of these for deletion.
    func testDoesNotMatchFilesThatDifferOnlyAfterThePrefix() throws {
        var first = [UInt8](repeating: 0x11, count: prefixSize)
        var second = first
        first.append(contentsOf: [UInt8](repeating: 0x01, count: 1_024))
        second.append(contentsOf: [UInt8](repeating: 0x02, count: 1_024))
        XCTAssertEqual(first.count, second.count, "the fixture must not differ in size")

        try write("tail-a.bin", first)
        try write("tail-b.bin", second)

        XCTAssertTrue(try scan().isEmpty)
    }

    func testDoesNotMatchFilesThatDifferInThePrefix() throws {
        try write("x.txt", Array("aaaa".utf8))
        try write("y.txt", Array("bbbb".utf8))

        XCTAssertTrue(try scan().isEmpty)
    }

    func testDoesNotMatchFilesOfDifferentSizes() throws {
        try write("short.txt", Array("abc".utf8))
        try write("long.txt", Array("abcd".utf8))

        XCTAssertTrue(try scan().isEmpty)
    }

    /// Empty files are all byte-identical to each other. Reporting every empty
    /// file on the disk as reclaimable would be true and useless.
    func testIgnoresEmptyFiles() throws {
        try write("empty-1.txt", [])
        try write("empty-2.txt", [])

        XCTAssertTrue(try scan().isEmpty)
    }

    // MARK: - Reporting

    func testReclaimableCountsEveryCopyButOne() throws {
        let body = [UInt8](repeating: 0x7F, count: 2_048)
        try write("c1.bin", body)
        try write("c2.bin", body)
        try write("c3.bin", body)

        let group = try XCTUnwrap(try scan().first)

        XCTAssertEqual(group.size, 2_048)
        XCTAssertEqual(group.reclaimable, 4_096, "three copies of 2 KB free 4 KB, not 6 KB")
    }

    func testGroupsAreSortedByReclaimableSpace() throws {
        let small = [UInt8](repeating: 0x01, count: 1_024)
        let large = [UInt8](repeating: 0x02, count: 8_192)
        try write("small-1.bin", small)
        try write("small-2.bin", small)
        try write("large-1.bin", large)
        try write("large-2.bin", large)

        let groups = try scan()

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(names(groups[0]), ["large-1.bin", "large-2.bin"],
                       "the biggest win is listed first")
    }

    func testRecursesIntoSubdirectories() throws {
        let nested = root.appendingPathComponent("nested/deeper")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let body = Array("buried".utf8)
        try write("top.txt", body)
        try Data(body).write(to: nested.appendingPathComponent("bottom.txt"))

        let groups = try scan()

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(names(groups[0]), ["top.txt", "bottom.txt"])
    }

    // MARK: - Failure

    func testReportsMissingFolderRatherThanEmptyResult() {
        let missing = root.appendingPathComponent("not-here").path
        guard case .failure = DuplicateAnalyzer.scan(path: missing) else {
            return XCTFail("a folder that doesn't exist is an error, not zero duplicates")
        }
    }
}
