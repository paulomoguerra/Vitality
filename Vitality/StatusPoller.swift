import Foundation
import OSLog
import WidgetKit

/// Owns `SystemMetrics` and serialises access to it.
///
/// `SystemMetrics` keeps the previous CPU tick sample between calls, so two
/// concurrent collections would corrupt each other's deltas and produce
/// nonsense percentages. A dedicated serial queue makes that impossible.
private final class MetricsEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.paulomateus.vitality.metrics", qos: .utility)
    private let metrics = SystemMetrics()

    func collect(_ completion: @escaping (SystemStatus) -> Void) {
        queue.async { completion(self.metrics.collect()) }
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
    private let widgetReloadInterval: TimeInterval = 30

    /// Collection is now pure in-process sysctl/Mach/IOKit calls costing under a
    /// millisecond, so this can be genuinely live. The old 3-second floor
    /// existed only because shelling out to a bash script was expensive.
    init(interval: TimeInterval = 1) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        engine.collect { [weak self] status in
            let writeError = SharedStatusStore.write(status)
            Task { @MainActor in
                guard let self else { return }
                if let writeError {
                    self.log.error("shared store write failed: \(writeError.localizedDescription, privacy: .public)")
                    self.lastError = writeError.localizedDescription
                } else {
                    self.lastError = nil
                }
                self.latest = status
                self.reloadWidgetsIfDue()
            }
        }
    }

    private func reloadWidgetsIfDue() {
        guard Date().timeIntervalSince(lastWidgetReload) >= widgetReloadInterval else { return }
        lastWidgetReload = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
