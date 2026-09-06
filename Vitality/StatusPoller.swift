import Foundation
import OSLog
import WidgetKit

/// Owns `SystemMetrics` and serialises access to it.
///
/// `SystemMetrics` keeps the previous CPU tick sample between calls, so two
/// concurrent collections would corrupt each other's deltas and produce
/// nonsense percentages. A dedicated serial queue makes that impossible. The
/// busy guard also rejects timer ticks while a slow collection is in progress,
/// rather than letting them form a backlog.
private final class MetricsEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.paulomateus.vitality.metrics", qos: .utility)
    private let metrics = SystemMetrics()
    private let stateLock = NSLock()
    private var isCollecting = false

    @discardableResult
    func collect(_ completion: @escaping (SystemStatus) -> Void) -> Bool {
        stateLock.lock()
        guard !isCollecting else {
            stateLock.unlock()
            return false
        }
        isCollecting = true
        stateLock.unlock()

        queue.async { [self] in
            defer {
                stateLock.lock()
                isCollecting = false
                stateLock.unlock()
            }
            completion(metrics.collect())
        }
        return true
    }
}

@MainActor
final class StatusPoller: ObservableObject {
    @Published private(set) var latest: SystemStatus?
    @Published private(set) var lastError: String?

    private let log = Logger(subsystem: "com.paulomateus.vitality", category: "poller")
    private let engine = MetricsEngine()
    private var timer: Timer?
    private var lastWidgetReload = Date.distantPast

    /// WidgetKit budgets how often an extension may reload. Asking on every
    /// poll would get Vitality throttled and refresh the widgets *less* often.
    ///
    /// The shared status file is written on the same clock. Its only reader is
    /// the widget extension, so encoding and atomically rewriting it once a
    /// second — thirty times more often than anything looked at it — was thirty
    /// times the work for the same result.
    private let widgetReloadInterval: TimeInterval = 30

    /// Keep a one-second cadence for live CPU and memory readings. SystemMetrics
    /// caches slower snapshots internally, and MetricsEngine skips a tick if a
    /// previous collection has not finished yet.
    init(interval: TimeInterval = 1) {
        refresh()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // A menu bar app is awake for the whole session, so its timer decides
        // how often the CPU has to wake at all. Slack lets the kernel coalesce
        // this tick with everything else that was due around the same moment,
        // which is free on accuracy and not free on battery.
        timer.tolerance = interval * 0.2
        self.timer = timer
    }

    deinit { timer?.invalidate() }

    func refresh() {
        let now = Date()
        let isWidgetRefreshDue = now.timeIntervalSince(lastWidgetReload) >= widgetReloadInterval

        engine.collect { [weak self] status in
            // The first CPU sample has no delta and reports nil. Publishing
            // that snapshot would pin widgets at 0% until the next 30s write.
            let publishWidget = isWidgetRefreshDue && status.cpu?.usage != nil
            let writeError = publishWidget ? SharedStatusStore.write(status) : nil
            Task { @MainActor in
                guard let self else { return }
                if let writeError {
                    self.log.error("shared store write failed: \(writeError.localizedDescription, privacy: .public)")
                    self.lastError = writeError.localizedDescription
                } else if publishWidget {
                    self.lastError = nil
                    self.lastWidgetReload = now
                    WidgetCenter.shared.reloadAllTimelines()
                }
                self.latest = status
            }
        }
    }
}
