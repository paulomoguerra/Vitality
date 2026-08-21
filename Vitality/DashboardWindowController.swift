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

    init(poller: StatusPoller, history: MetricsHistoryStore, alerts: AlertCenter) {
        self.poller = poller
        self.history = history
        self.alerts = alerts
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(
            rootView: DashboardView(poller: poller, history: history, alerts: alerts))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Vitality"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 520))
        window.center()
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
}
