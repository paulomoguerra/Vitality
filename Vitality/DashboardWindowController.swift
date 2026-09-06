import AppKit
import SwiftUI

/// Owns the dashboard window.
///
/// Vitality is an `LSUIElement` app — no Dock icon, no menu bar menu — so
/// AppKit won't route window activation for us. Opening the dashboard has to
/// explicitly activate the app, or the window appears behind whatever the user
/// was looking at.
@MainActor
final class DashboardWindowController {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private let poller: StatusPoller
    private let history: MetricsHistoryStore
    private let alerts: AlertCenter
    private let router = DashboardRouter()

    init(poller: StatusPoller, history: MetricsHistoryStore, alerts: AlertCenter) {
        self.poller = poller
        self.history = history
        self.alerts = alerts
    }

    /// Brings the dashboard forward without changing the current destination.
    /// Generic “Open dashboard…” must not bounce an already-open window back
    /// to Overview.
    func show() {
        presentWindow()
    }

    func show(section: DashboardSection) {
        router.open(section)
        presentWindow()
    }

    private func presentWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(
            rootView: DashboardView(poller: poller, history: history, alerts: alerts, router: router)
                .preferredColorScheme(.dark)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Vitality"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 1020, height: 680))
        window.minSize = NSSize(width: 760, height: 500)
        window.setFrameAutosaveName("VitalityDashboard")
        window.backgroundColor = Theme.pageBgNS
        window.appearance = NSAppearance(named: .darkAqua)
        if !window.setFrameUsingName("VitalityDashboard") {
            window.center()
        }
        window.isReleasedWhenClosed = false

        // Tear the window down on close rather than keeping it around. A kept
        // window keeps its SwiftUI tree observing the 1 Hz poller — charts and
        // insights re-evaluated every second for a window nobody can see.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue, synchronously with the close — no
            // async hop, so a re-open can never catch the dying window.
            MainActor.assumeIsolated {
                guard let self else { return }
                if let closeObserver = self.closeObserver {
                    NotificationCenter.default.removeObserver(closeObserver)
                }
                self.closeObserver = nil
                self.window = nil
            }
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func show(alert rule: AlertRuleID) {
        router.open(alert: rule)
        presentWindow()
    }
}
