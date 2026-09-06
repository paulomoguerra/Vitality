import Cocoa
import Combine
import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private let log = Logger(subsystem: "com.paulomateus.vitality", category: "app")
    private var menuBar: MenuBarStatusItemController!
    /// Created before the Settings scene is rendered, so the native Settings
    /// window and the menu bar always edit the same object.
    private let settings = MenuBarSettings()
    private var history: MenuBarHistory!
    private var popover: NSPopover!
    private var poller: StatusPoller!
    private var metricsHistory: MetricsHistoryStore!
    private var alerts: AlertCenter!
    private var dashboard: DashboardWindowController!
    private var eventMonitor: Any?
    private var launchAtLoginObservation: AnyCancellable?

    /// Settings is a SwiftUI scene, while the monitor is owned by AppKit. A
    /// published handoff keeps the scene unavailable only during the very short
    /// launch gap and avoids a second poller or AlertCenter.
    @Published private(set) var statusPollerForUI: StatusPoller?
    @Published private(set) var alertCenterForUI: AlertCenter?
    @Published private(set) var menuBarHistoryForUI: MenuBarHistory?

    var settingsForUI: MenuBarSettings { settings }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchAtLoginObservation = settings.$launchAtLogin
            .dropFirst()
            .sink { enabled in
                LoginItem.apply(enabled: enabled)
            }
        // Register only after the person has explicitly configured this
        // preference. The first launch must not create a login item silently.
        if settings.hasConfiguredLaunchAtLogin {
            LoginItem.apply(enabled: settings.launchAtLogin)
        }

        poller = StatusPoller()
        statusPollerForUI = poller
        // Both live for the whole session, not the dashboard window's: history
        // accrues and alerts watch (and notify) whether or not any UI is open.
        metricsHistory = MetricsHistoryStore(poller: poller)
        alerts = AlertCenter(poller: poller)
        alertCenterForUI = alerts
        dashboard = DashboardWindowController(poller: poller,
                                              history: metricsHistory,
                                              alerts: alerts)
        alerts.onOpenAlert = { [weak self] rule in
            self?.dashboard.show(alert: rule)
        }

        history = MenuBarHistory(poller: poller, settings: settings)
        menuBarHistoryForUI = history
        menuBar = MenuBarStatusItemController(poller: poller, settings: settings,
                                              history: history, alerts: alerts)
        if let button = menuBar.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(poller: poller,
                                  settings: settings,
                                  history: history,
                                  alerts: alerts,
                                  onOpenDashboard: { [weak self] section in
                self?.openDashboard(section: section)
            },
                                  onOpenSettings: { [weak self] in
                self?.openSettings()
            },
                                  onOpenAlert: { [weak self] rule in
                self?.popover.performClose(nil)
                self?.dashboard.show(alert: rule)
            })
            .preferredColorScheme(.dark)
        )

        // No setup step: Vitality measures everything itself, so it works the
        // moment it launches with nothing to install first.
        log.info("launch: native metrics, no external dependency")
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeEventMonitor()
        metricsHistory.flush()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, dashboard != nil else { return true }
        dashboard.show()
        return true
    }

    /// Deep links keep notifications, widgets and other macOS surfaces on the
    /// same route. The URL scheme itself is declared in project.yml; this
    /// handler deliberately accepts only dashboard sections we know.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "vitality", url.host == "dashboard",
                  let rawSection = url.pathComponents.dropFirst().first,
                  let section = DashboardSection.allCases.first(where: {
                      $0.rawValue.caseInsensitiveCompare(rawSection) == .orderedSame
                  }),
                  let dashboard else { continue }
            dashboard.show(section: section)
        }
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

    private func openDashboard(section: DashboardSection? = nil) {
        // Close the popover first — it's `.transient`, and leaving it up while
        // a real window takes focus looks like a glitch.
        popover.performClose(nil)
        if let section {
            dashboard.show(section: section)
        } else {
            dashboard.show()
        }
    }

    private func openSettings() {
        popover.performClose(nil)
        // `Settings` scene owns the actual window and command routing. This is
        // the AppKit bridge that lets a compact menu bar button reach it.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
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
