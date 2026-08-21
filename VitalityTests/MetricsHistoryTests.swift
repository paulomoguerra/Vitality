import XCTest

/// `HistoryTier` is where a week of the machine's life gets compressed into a
/// thousand points. Everything the dashboard charts claim — this was the peak,
/// this was the average, this is how far back the data goes — is this
/// arithmetic, and none of it is visible enough to catch by looking.
final class MetricsHistoryTests: XCTestCase {

    // MARK: - Builders

    /// A round timestamp, so bucket boundaries in the tests are the same ones
    /// the aligned grid produces.
    private let origin = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ offset: TimeInterval) -> Date {
        origin.addingTimeInterval(offset)
    }

    private func tier(interval: TimeInterval = 5, capacity: Int = 3) -> HistoryTier {
        HistoryTier(interval: interval, capacity: capacity)
    }

    private func bucket(_ offset: TimeInterval, average: Double = 1, peak: Double = 1) -> HistoryBucket {
        HistoryBucket(date: at(offset), average: average, peak: peak)
    }

    // MARK: - Commit boundaries

    /// A bucket that is still filling is not a measurement yet, so it stays out
    /// of the series until its window has actually passed.
    func testTheOpenBucketIsNotPublishedUntilItsWindowPasses() {
        var tier = self.tier()

        XCTAssertFalse(tier.add(value: 10, at: at(0)))
        XCTAssertFalse(tier.add(value: 20, at: at(4.9)))
        XCTAssertTrue(tier.committed.isEmpty)

        XCTAssertTrue(tier.add(value: 30, at: at(5)), "crossing the boundary commits")
        XCTAssertEqual(tier.committed.count, 1)
    }

    /// Buckets are pinned to absolute time, not to whenever the first sample
    /// happened to land — that is what lets a relaunched app resume the grid it
    /// left rather than start a new one half a bucket out of phase.
    func testBucketsAreAlignedToAbsoluteTimeNotToTheFirstSample() {
        var tier = self.tier()

        tier.add(value: 1, at: at(3))    // lands in the bucket starting at 0
        tier.add(value: 1, at: at(7))

        XCTAssertEqual(tier.committed.first?.date, at(0))
    }

    /// The clock moved backwards. Accepting the sample would append a point
    /// behind the one before it.
    func testSamplesOlderThanTheOpenBucketAreIgnored() {
        var tier = self.tier()

        tier.add(value: 10, at: at(10))
        XCTAssertFalse(tier.add(value: 99, at: at(2)))
        tier.add(value: 10, at: at(15))

        XCTAssertEqual(tier.committed.count, 1)
        XCTAssertEqual(tier.committed.first?.average, 10, "the stray sample did not fold in")
    }

    /// Sleep and wake leaves a hole in the samples. As long as the hole fits
    /// inside the tier's window, the tier commits what it had and opens the
    /// bucket the next sample belongs to, rather than inventing the buckets in
    /// between. (A hole *wider* than the window evicts instead — see the
    /// long-sleep test.)
    func testAGapInSamplesLeavesAGapNotInventedBuckets() {
        var tier = self.tier(capacity: 200)   // window: 200 × 5 s = 1,000 s

        tier.add(value: 1, at: at(0))
        tier.add(value: 2, at: at(600))

        XCTAssertEqual(tier.committed.count, 1)
        XCTAssertEqual(tier.committed.first?.date, at(0))
    }

    // MARK: - Aggregation

    func testACommittedBucketCarriesItsAverageAndItsPeak() {
        var tier = self.tier()

        tier.add(value: 10, at: at(0))
        tier.add(value: 90, at: at(1))
        tier.add(value: 20, at: at(2))
        tier.add(value: 0, at: at(5))

        XCTAssertEqual(tier.committed.first?.average, 40)
        XCTAssertEqual(tier.committed.first?.peak, 90)
    }

    /// The peak has to survive averaging. A 90% spike inside a bucket that
    /// averages 40% is the number worth reporting, and the maximum of a set of
    /// averages would never find it.
    func testStatsReportTheHighestSampleNotTheHighestAverage() {
        var tier = self.tier(capacity: 10)

        tier.add(value: 10, at: at(0))
        tier.add(value: 90, at: at(1))   // bucket 0: average 50, peak 90
        tier.add(value: 60, at: at(5))   // bucket 1: average 60, peak 60
        tier.add(value: 0, at: at(10))   // closes bucket 1

        let stats = tier.stats
        XCTAssertEqual(stats?.average, 55)
        XCTAssertEqual(stats?.peak, 90)
    }

    /// "No data" and "zero" are different answers, and a chart that shows 0 for
    /// a metric it has never seen is lying about the Mac.
    func testStatsAreNilBeforeAnyBucketCloses() {
        var tier = self.tier()

        XCTAssertNil(tier.stats)
        tier.add(value: 50, at: at(0))
        XCTAssertNil(tier.stats, "an open bucket is not a result yet")
    }

    func testPointsExposeTheBucketAverage() {
        var tier = self.tier(capacity: 10)

        tier.add(value: 30, at: at(0))
        tier.add(value: 50, at: at(1))
        tier.add(value: 0, at: at(5))

        XCTAssertEqual(tier.points.count, 1)
        XCTAssertEqual(tier.points.first?.value, 40)
        XCTAssertEqual(tier.points.first?.date, at(0))
    }

    // MARK: - Capacity

    /// Each tier covers a fixed span, so the oldest bucket has to fall off the
    /// front as a new one closes — otherwise the "1 h" chart quietly becomes a
    /// chart of the whole session.
    func testTheOldestBucketIsDroppedOnceCapacityIsReached() {
        var tier = self.tier(capacity: 2)

        for step in 0...3 {
            tier.add(value: Double(step), at: at(Double(step) * 5))
        }

        XCTAssertEqual(tier.committed.count, 2)
        XCTAssertEqual(tier.committed.map(\.date), [at(5), at(10)])
    }

    /// Capacity alone only evicts one bucket per new commit. After a night of
    /// sleep the poller resumes with a full tier of yesterday, and without age
    /// eviction the "1 h" chart would span sixteen hours until enough new
    /// buckets had shoved the old ones out one at a time.
    func testWakingAfterALongSleepEvictsTheStaleWindowAtOnce() {
        var tier = self.tier(interval: 5, capacity: 3)

        for step in 0...3 {
            tier.add(value: 1, at: at(Double(step) * 5))
        }
        XCTAssertEqual(tier.committed.count, 3, "tier is full before the sleep")

        // Window is 15 s; wake up an hour later.
        XCTAssertTrue(tier.add(value: 2, at: at(3_600)), "eviction alone must trigger a redraw")

        XCTAssertTrue(tier.committed.isEmpty, "everything stale left in one step")

        tier.add(value: 2, at: at(3_605))
        XCTAssertEqual(tier.committed.map(\.date), [at(3_600)], "the live series carries on")
    }

    // MARK: - Restoring from disk

    /// The file on disk can be days old. Anything past the tier's window is
    /// dropped on load, so a chart never claims to cover more time than it has.
    func testRestoringDropsBucketsOlderThanTheWindow() {
        // Window is 3 × 5 s = 15 s back from "now".
        let restored = HistoryTier(interval: 5, capacity: 3,
                                   restoring: [bucket(-100), bucket(-10), bucket(-5)],
                                   now: at(0))

        XCTAssertEqual(restored.committed.map(\.date), [at(-10), at(-5)])
    }

    func testRestoringTrimsToCapacityKeepingTheNewest() {
        let restored = HistoryTier(interval: 5, capacity: 2,
                                   restoring: [bucket(-9), bucket(-6), bucket(-3)],
                                   now: at(0))

        XCTAssertEqual(restored.committed.map(\.date), [at(-6), at(-3)])
    }

    /// A file written before the clock was corrected can hold buckets dated in
    /// the future. They are not history.
    func testRestoringDropsFutureDatedBuckets() {
        let restored = HistoryTier(interval: 5, capacity: 3,
                                   restoring: [bucket(-5), bucket(500)],
                                   now: at(0))

        XCTAssertEqual(restored.committed.map(\.date), [at(-5)])
    }

    /// Restored history and live samples are the same series, so the first
    /// sample after a relaunch must extend it rather than replace it.
    func testRestoredBucketsSurviveTheNextLiveSample() {
        var restored = HistoryTier(interval: 5, capacity: 3,
                                   restoring: [bucket(-10, average: 42, peak: 42)],
                                   now: at(0))

        restored.add(value: 1, at: at(0))
        restored.add(value: 1, at: at(5))

        XCTAssertEqual(restored.committed.count, 2)
        XCTAssertEqual(restored.committed.first?.average, 42)
    }
}
