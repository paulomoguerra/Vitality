import XCTest

final class FormatterTests: XCTestCase {

    func testNilBytesReadsAsMissingNotZero() {
        XCTAssertEqual(Fmt.bytes(nil), "—")
    }

    /// A full volume has 0 bytes free. That has to read as zero, not as a
    /// missing measurement — the dash would hide the exact condition Vitality
    /// exists to surface.
    func testZeroBytesIsARealReading() {
        XCTAssertNotEqual(Fmt.bytes(0), "—")
        XCTAssertFalse(Fmt.bytes(0).isEmpty)
    }

    func testNegativeBytesReadAsMissing() {
        XCTAssertEqual(Fmt.bytes(-1), "—")
    }

    /// Below a KB/s the exact figure flickers. Idle has to be a real zero
    /// rate, not a dash — a quiet link is not a missing measurement.
    func testRateBelowAKilobyteReadsAsIdle() {
        XCTAssertEqual(Fmt.rate(nil), "—")
        XCTAssertEqual(Fmt.rate(0), "0 KB/s")
        XCTAssertEqual(Fmt.rate(999), "0 KB/s")
    }

    func testLoadRatioNeedsAPositiveCoreCount() {
        XCTAssertNil(Fmt.loadRatio(4, cores: nil))
        XCTAssertNil(Fmt.loadRatio(4, cores: 0))
        XCTAssertEqual(Fmt.loadRatio(4, cores: 8), 50)
    }
}
