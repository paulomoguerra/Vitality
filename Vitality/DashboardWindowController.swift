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
    private let poller: StatusPoller

    init(poller: StatusPoller) {
        self.poller = poller
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: DashboardView(poller: poller))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Vitality"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 520))
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
