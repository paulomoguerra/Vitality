import XCTest

final class StatusFreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFreshSnapshotIsLive() {
        let collectedAt = now.addingTimeInterval(-30)

        XCTAssertEqual(StatusFreshness.state(collectedAt: collectedAt, now: now), .live)
    }

    func testSnapshotAtFiveMinuteBoundaryIsStale() {
        let collectedAt = now.addingTimeInterval(-5 * 60)

        XCTAssertEqual(StatusFreshness.state(collectedAt: collectedAt, now: now), .stale)
    }

    func testMissingTimestampCannotClaimLiveData() {
        XCTAssertEqual(StatusFreshness.state(collectedAt: nil, now: now), .unknown)
    }

    func testFutureTimestampWithinClockToleranceIsLive() {
        let collectedAt = now.addingTimeInterval(30)

        XCTAssertEqual(StatusFreshness.state(collectedAt: collectedAt, now: now), .live)
    }

    func testFarFutureTimestampIsUnknown() {
        let collectedAt = now.addingTimeInterval(30 * 60)

        XCTAssertEqual(StatusFreshness.state(collectedAt: collectedAt, now: now), .unknown)
    }

    /// The five-minute mark is stale; one second earlier is still live.
    /// The inequality is the whole policy.
    func testSnapshotJustUnderFiveMinutesIsLive() {
        let collectedAt = now.addingTimeInterval(-5 * 60 + 1)

        XCTAssertEqual(StatusFreshness.state(collectedAt: collectedAt, now: now), .live)
    }
}
