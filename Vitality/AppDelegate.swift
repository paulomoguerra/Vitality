import Cocoa
import Combine
import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.paulomateus.vitality", category: "app")
    private var menuBar: MenuBarStatusItemController!
    private var settings: MenuBarSettings!
    private var history: MenuBarHistory!
    private var popover: NSPopover!
    private var poller: StatusPoller!
    private var metricsHistory: MetricsHistoryStore!
    private var alerts: AlertCenter!
    private var dashboard: DashboardWindowController!
    private var eventMonitor: Any?
    private var launchAtLoginObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = MenuBarSettings()
        launchAtLoginObservation = settings.$launchAtLogin
            .dropFirst()
            .sink { enabled in
                LoginItem.apply(enabled: enabled)
            }
        LoginItem.apply(enabled: settings.launchAtLogin)

        poller = StatusPoller()
        // Both live for the whole session, not the dashboard window's: history
        // accrues and alerts watch (and notify) whether or not any UI is open.
        metricsHistory = MetricsHistoryStore(poller: poller)
        alerts = AlertCenter(poller: poller)
        dashboard = DashboardWindowController(poller: poller,
                                              history: metricsHistory,
                                              alerts: alerts)

        history = MenuBarHistory(poller: poller, settings: settings)
        menuBar = MenuBarStatusItemController(poller: poller, settings: settings, history: history)
        if let button = menuBar.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(poller: poller,
                                  settings: settings,
                                  history: history,
                                  onOpenDashboard: { [weak self] in
                self?.openDashboard()
            })
        )

        // No setup step: Vitality measures everything itself, so it works the
        // moment it launches with nothing to install first.
        log.info("launch: native metrics, no external dependency")
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeEventMonitor()
        metricsHistory.flush()
    }

    /// Backstop for `.transient`, which doesn't always close a status-item
    /// popover when another app's window takes the click. Installed only while
    /// the popover is up — a global monitor wakes the app on every click
    /// anywhere in macOS, so it must not outlive the one moment it serves.
    private func installEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    private func openDashboard() {
        // Close the popover first — it's `.transient`, and leaving it up while
        // a real window takes focus looks like a glitch.
        popover.performClose(nil)
        dashboard.show()
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = menuBar.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            installEventMonitor()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // The popover hosts its own SwiftUI content; make it key so text
            // fields and buttons inside respond to the first click.
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        // A fast re-open can install a fresh monitor before this close's
        // notification lands; don't tear down the backstop of a live popover.
        guard !popover.isShown else { return }
        removeEventMonitor()
    }
}
