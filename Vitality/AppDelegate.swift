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
        dashboard = DashboardWindowController(poller: poller)

        history = MenuBarHistory(poller: poller)
        menuBar = MenuBarStatusItemController(poller: poller, settings: settings, history: history)
        if let button = menuBar.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(poller: poller,
                                  settings: settings,
                                  history: history,
                                  onOpenDashboard: { [weak self] in
                self?.openDashboard()
            })
        )

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }

        // No setup step: Vitality measures everything itself, so it works the
        // moment it launches with nothing to install first.
        log.info("launch: native metrics, no external dependency")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // The popover hosts its own SwiftUI content; make it key so text
            // fields and buttons inside respond to the first click.
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
