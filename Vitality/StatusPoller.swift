import Foundation
import OSLog
import WidgetKit

@MainActor
final class StatusPoller: ObservableObject {
    @Published private(set) var latest: SystemStatus?
    @Published private(set) var lastError: MoleError?

    private let log = Logger(subsystem: "com.paulomateus.vitality", category: "poller")

    private var timer: Timer?
    private var lastWidgetReload = Date.distantPast

    /// True while a `mo status` run is in flight.
    ///
    /// `mo` is a shell script that forks dozens of helpers and takes a few
    /// seconds. Without this guard the timer starts a new run before the last
    /// one finishes, they contend, and every run trips its own timeout — so the
    /// app burns CPU continuously and never produces a single usable result.
    private var isCollecting = false

    /// WidgetKit budgets how often an extension may reload. Asking on every
    /// poll would get Vitality throttled and make widgets update *less* often.
    private let widgetReloadInterval: TimeInterval = 30

    init(interval: TimeInterval = 3) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        guard !isCollecting else {
            log.debug("skipping poll — previous mo run still in flight")
            return
        }
        isCollecting = true

        Task.detached(priority: .utility) { [weak self] in
            let result = StatusCollector.collect()

            // Persist off the main actor — the widget reads this file, and a
            // disk write has no business blocking the UI.
            var writeError: Error?
            if case .success(let status) = result {
                writeError = SharedStatusStore.write(status)
            }

            await MainActor.run {
                guard let self else { return }
                self.isCollecting = false

                switch result {
                case .success(let status):
                    if let writeError {
                        self.log.error("shared store write failed: \(writeError.localizedDescription, privacy: .public)")
                    }
                    self.latest = status
                    self.lastError = nil
                    self.reloadWidgetsIfDue()
                case .failure(let error):
                    self.log.error("mo status failed: \(error.localizedDescription, privacy: .public)")
                    self.lastError = error
                }
            }
        }
    }

    private func reloadWidgetsIfDue() {
        guard Date().timeIntervalSince(lastWidgetReload) >= widgetReloadInterval else { return }
        lastWidgetReload = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
