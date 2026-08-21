import Combine
import Foundation
import OSLog

/// The three windows the dashboard charts offer.
enum HistoryRange: String, CaseIterable, Identifiable {
    case hour, day, week

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hour: return "1 h"
        case .day:  return "24 h"
        case .week: return "7 d"
        }
    }

    /// How much time one bucket covers.
    ///
    /// The three tiers are sized so each holds roughly a thousand points: fine
    /// enough that a spike is still visible after averaging, coarse enough that
    /// a week of history is a file you never think about.
    var bucketInterval: TimeInterval {
        switch self {
        case .hour: return 5
        case .day:  return 60
        case .week: return 600
        }
    }

    /// 720 × 5 s = 1 h, 1440 × 60 s = 24 h, 1008 × 600 s = 7 d.
    var bucketCapacity: Int {
        switch self {
        case .hour: return 720
        case .day:  return 1440
        case .week: return 1008
        }
    }
}

enum HistoryMetric: String, CaseIterable {
    case cpu, gpu, memory, disk, power, netDown, netUp

    /// A missing reading is not a zero. Returning nil keeps it out of the
    /// bucket entirely, so a Mac with no SMC power rail draws no power line
    /// rather than a flat one along the floor.
    func value(in status: SystemStatus) -> Double? {
        switch self {
        case .cpu:     return status.cpu?.usage
        case .gpu:     return status.gpu?.utilization
        case .memory:  return status.memory?.usedPercent
        case .disk:    return status.primaryDisk?.usedPercent
        case .power:   return status.headlinePower
        case .netDown: return status.network?.downBytesPerSec
        case .netUp:   return status.network?.upBytesPerSec
        }
    }
}

/// One day's battery health. Capacity and cycles move on the scale of weeks, so
/// a daily entry is all the resolution the number has.
struct BatteryDay: Codable, Equatable {
    let day: Date
    let capacityPercent: Int
    let cycleCount: Int?
}

/// Persistent metrics history for the dashboard charts.
///
/// This answers a question the live readouts can't — what has this Mac been
/// doing this week — and to answer it at all it has to survive relaunches, so
/// it aggregates rather than records: 1 Hz samples fold into fixed buckets
/// (see `HistoryTier`), and only a closed bucket is ever published or written.
///
/// That folding is the reason `revision` exists instead of an `@Published`
/// array. A published sample per poll would redraw every chart once a second to
/// move a line by a pixel; a counter that ticks when a bucket closes redraws
/// them when the picture has actually changed — at most every 5 s.
@MainActor
final class MetricsHistoryStore: ObservableObject {

    /// Bumped whenever a bucket commits, so views can observe cheap redraws.
    @Published private(set) var revision = 0

    /// Not published: the battery chart moves once a day, and the dashboard
    /// reads it when it opens.
    private(set) var batteryHealthDays: [BatteryDay] = []

    private struct TierKey: Hashable {
        let range: HistoryRange
        let metric: HistoryMetric
    }

    /// `allCases` builds a fresh array on every access, and this runs at 1 Hz
    /// for the life of the app.
    private static let metrics = HistoryMetric.allCases
    private static let ranges = HistoryRange.allCases

    private static let saveInterval: TimeInterval = 300
    private static let batteryDayCapacity = 400

    private var tiers: [TierKey: HistoryTier] = [:]
    private var cancellable: AnyCancellable?
    private var lastSave = Date()
    private var lastBatteryEntry: BatteryDay?
    private let calendar = Calendar.current

    init(poller: StatusPoller) {
        let archive = HistoryArchiveStore.load()
        let now = Date()
        for range in Self.ranges {
            for metric in Self.metrics {
                tiers[TierKey(range: range, metric: metric)] = HistoryTier(
                    interval: range.bucketInterval,
                    capacity: range.bucketCapacity,
                    restoring: archive?.buckets(range, metric) ?? [],
                    now: now
                )
            }
        }
        batteryHealthDays = archive?.battery ?? []
        lastBatteryEntry = batteryHealthDays.last

        cancellable = poller.$latest.sink { [weak self] status in
            self?.record(status)
        }
    }

    func series(_ metric: HistoryMetric, range: HistoryRange) -> [HistoryPoint] {
        tiers[TierKey(range: range, metric: metric)]?.points ?? []
    }

    func stats(_ metric: HistoryMetric, range: HistoryRange) -> (average: Double, peak: Double)? {
        tiers[TierKey(range: range, metric: metric)]?.stats
    }

    /// Persist now. Called from app termination, where an async write would
    /// lose the race against the process going away.
    func flush() {
        lastSave = Date()
        save(synchronously: true)
    }

    // MARK: - Recording

    private func record(_ status: SystemStatus?) {
        guard let status else { return }
        // The sample's own timestamp, not the moment it arrived: the buckets it
        // lands in should describe when the Mac was measured.
        let now = status.collectedAt ?? Date()

        // Twenty-one in-place mutations through the dictionary and nothing
        // else — no scratch array, no intermediate snapshot. Allocation happens
        // only when a bucket closes.
        var didCommit = false
        for metric in Self.metrics {
            guard let value = metric.value(in: status) else { continue }
            for range in Self.ranges {
                if tiers[TierKey(range: range, metric: metric)]?.add(value: value, at: now) == true {
                    didCommit = true
                }
            }
        }

        recordBatteryHealth(status, now: now)

        if didCommit { revision &+= 1 }

        if now.timeIntervalSince(lastSave) >= Self.saveInterval {
            lastSave = now
            save(synchronously: false)
        }
    }

    /// One entry per calendar day, updated in place while the day is still
    /// running. The reading is compared against the last one first: without
    /// that, every poll would rescan the array to write the same numbers back.
    private func recordBatteryHealth(_ status: SystemStatus, now: Date) {
        guard let capacityPercent = status.battery?.capacity else { return }

        let entry = BatteryDay(day: calendar.startOfDay(for: now),
                               capacityPercent: capacityPercent,
                               cycleCount: status.battery?.cycleCount)
        guard entry != lastBatteryEntry else { return }
        lastBatteryEntry = entry

        if let index = batteryHealthDays.lastIndex(where: { $0.day == entry.day }) {
            batteryHealthDays[index] = entry
        } else {
            batteryHealthDays.append(entry)
            if batteryHealthDays.count > Self.batteryDayCapacity {
                batteryHealthDays.removeFirst(batteryHealthDays.count - Self.batteryDayCapacity)
            }
        }
    }

    // MARK: - Persistence

    private func save(synchronously: Bool) {
        let archive = HistoryArchive(
            series: tiers.map {
                HistoryArchive.Series(range: $0.key.range.rawValue,
                                      metric: $0.key.metric.rawValue,
                                      buckets: $0.value.committed)
            },
            battery: batteryHealthDays
        )

        if synchronously {
            // Through the same serial queue as the timed writes, or an
            // in-flight five-minute-old write could rename over this one and
            // lose the final window of history.
            HistoryArchiveStore.queue.sync { HistoryArchiveStore.write(archive) }
        } else {
            HistoryArchiveStore.queue.async { HistoryArchiveStore.write(archive) }
        }
    }
}

/// The on-disk shape.
///
/// Flat records rather than a dictionary keyed by "range.metric": those keys
/// would have to be parsed apart again on load, and a series whose range or
/// metric no longer exists should simply be skipped by the lookup rather than
/// break the decode of everything beside it.
private struct HistoryArchive: Codable, Sendable {

    struct Series: Codable, Sendable {
        let range: String
        let metric: String
        let buckets: [HistoryBucket]
    }

    static let currentVersion = 1

    var version = HistoryArchive.currentVersion
    let series: [Series]
    let battery: [BatteryDay]

    func buckets(_ range: HistoryRange, _ metric: HistoryMetric) -> [HistoryBucket] {
        series.first { $0.range == range.rawValue && $0.metric == metric.rawValue }?.buckets ?? []
    }
}

private enum HistoryArchiveStore {

    /// Encoding twenty thousand buckets is not main-thread work, and the timed
    /// write must never interleave with a flush. One serial queue gives both.
    static let queue = DispatchQueue(label: "com.paulomateus.vitality.history", qos: .utility)

    private static let log = Logger(subsystem: "com.paulomateus.vitality", category: "history")

    /// Vitality is unsandboxed, so this is the real
    /// `~/Library/Application Support/Vitality/history.json` — not a container.
    static let fileURL: URL? = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return base?
            .appendingPathComponent("Vitality", isDirectory: true)
            .appendingPathComponent("history.json")
    }()

    static func write(_ archive: HistoryArchive) {
        guard let url = fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            // Seconds since 1970 rather than ISO-8601: a third of the bytes
            // across ~20k timestamps, and no locale or calendar in the path.
            encoder.dateEncodingStrategy = .secondsSince1970
            // Atomic, so a crash mid-write can't leave a truncated file that
            // the next launch would throw away wholesale.
            try encoder.encode(archive).write(to: url, options: .atomic)
        } catch {
            // History is a convenience. Failing to keep it is worth a log line
            // and nothing more.
            log.error("history write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Missing, corrupt or written by a newer build — all the same answer:
    /// start empty. History is worth losing before it is worth a crash.
    static func load() -> HistoryArchive? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let archive = try? decoder.decode(HistoryArchive.self, from: data),
              archive.version == HistoryArchive.currentVersion else { return nil }
        return archive
    }
}
