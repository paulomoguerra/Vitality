import Foundation

/// The bucketing core of `MetricsHistoryStore`, in its own file so the test
/// target can compile it without dragging the poller, Combine, and the whole
/// metrics engine along.

struct HistoryPoint: Equatable {
    let date: Date
    let value: Double
}

/// A closed bucket: the average that gets drawn, plus the highest sample inside
/// it. Keeping the peak separately is what lets `stats` report a real maximum —
/// the maximum of a set of averages is not a maximum of anything.
struct HistoryBucket: Codable, Equatable, Sendable {
    let date: Date
    let average: Double
    let peak: Double
}

/// One metric at one resolution: the pure bucketing core, with no clock, no
/// poller and no main actor of its own, so the aggregation can be tested for
/// what it is — arithmetic over timestamps.
struct HistoryTier {
    let interval: TimeInterval
    let capacity: Int

    /// Closed buckets, oldest first.
    ///
    /// A plain array with `removeFirst` on overflow, not a ring buffer: a
    /// bucket closes at most once every 5 s even in the tightest tier, while
    /// the charts read the whole series on every redraw. Paying one shift on
    /// the rare operation to hand the common one its points already in order is
    /// the right way round.
    private(set) var committed: [HistoryBucket] = []

    /// The bucket currently accumulating. It is deliberately not part of
    /// `committed` — a half-filled average is not a measurement yet.
    private var openStart: Date?
    private var sum = 0.0
    private var peak = 0.0
    private var count = 0

    init(interval: TimeInterval,
         capacity: Int,
         restoring buckets: [HistoryBucket] = [],
         now: Date = Date()) {
        self.interval = interval
        self.capacity = capacity

        // Anything that fell out of the window while the app was closed is
        // dropped here rather than on read, so a stale file can never make a
        // chart claim to cover more time than it does. Future-dated buckets go
        // too: they can only come from a clock that has since been corrected.
        let cutoff = now.addingTimeInterval(-interval * Double(capacity))
        var kept = buckets
            .filter { $0.date >= cutoff && $0.date <= now }
            .sorted { $0.date < $1.date }
        if kept.count > capacity { kept.removeFirst(kept.count - capacity) }
        committed = kept
    }

    /// Feeds one sample in. Returns true when the committed series changed,
    /// which is the only moment anything downstream has to redraw.
    @discardableResult
    mutating func add(value: Double, at date: Date) -> Bool {
        let start = bucketStart(for: date)

        // After a restore there is no open bucket, so the backwards-clock
        // guard below would not fire. A sample that lands in the last
        // committed window — or earlier — must not open that window
        // again: committing it would duplicate a point the charts already
        // have, and an older one would draw a line flying back.
        if openStart == nil, let last = committed.last, start <= last.date {
            return false
        }

        // Capacity alone is not enough of a window: the poller stops while the
        // Mac sleeps, so a lid opened in the morning would otherwise wake to a
        // "1 h" chart still holding yesterday evening — sixteen hours smeared
        // under a one-hour label, evicted one bucket at a time. Age them out
        // against the incoming sample instead.
        let cutoff = start.addingTimeInterval(-interval * Double(capacity))
        var didEvict = false
        if let firstFresh = committed.firstIndex(where: { $0.date >= cutoff }) {
            if firstFresh > 0 { committed.removeFirst(firstFresh); didEvict = true }
        } else if !committed.isEmpty {
            committed.removeAll()
            didEvict = true
        }

        guard let open = openStart else {
            openStart = start
            accumulate(value)
            return didEvict
        }

        // The clock moved backwards. Accepting the sample would append a point
        // behind the one before it, which every chart draws as a line flying
        // back across itself.
        guard start >= open else { return didEvict }

        var didCommit = false
        if start > open {
            // The bucket that was accumulating when the machine went to sleep
            // is subject to the same window as its committed peers: closing it
            // now would date it before the cutoff and reintroduce exactly the
            // stale point the eviction above just removed.
            if open >= cutoff {
                commit(at: open)
                didCommit = true
            } else {
                discardOpen()
                didEvict = true
            }
            openStart = start
        }
        accumulate(value)
        return didCommit || didEvict
    }

    var points: [HistoryPoint] {
        committed.map { HistoryPoint(date: $0.date, value: $0.average) }
    }

    /// The average of the bucket averages — which is only the true average
    /// because every bucket covers the same span — and the highest single
    /// sample seen anywhere in the window.
    var stats: (average: Double, peak: Double)? {
        guard !committed.isEmpty,
              let highest = committed.max(by: { $0.peak < $1.peak })?.peak else { return nil }
        let total = committed.reduce(0.0) { $0 + $1.average }
        return (total / Double(committed.count), highest)
    }

    /// Buckets are aligned to absolute time rather than to the first sample, so
    /// two tiers started at different moments still line up, and a restarted
    /// app carries on with the same grid it left.
    private func bucketStart(for date: Date) -> Date {
        let seconds = date.timeIntervalSince1970
        return Date(timeIntervalSince1970: (seconds / interval).rounded(.down) * interval)
    }

    private mutating func discardOpen() {
        sum = 0
        peak = 0
        count = 0
    }

    private mutating func accumulate(_ value: Double) {
        sum += value
        peak = count == 0 ? value : max(peak, value)
        count += 1
    }

    private mutating func commit(at start: Date) {
        guard count > 0 else { return }
        committed.append(HistoryBucket(date: start, average: sum / Double(count), peak: peak))
        if committed.count > capacity { committed.removeFirst(committed.count - capacity) }
        sum = 0
        peak = 0
        count = 0
    }
}
