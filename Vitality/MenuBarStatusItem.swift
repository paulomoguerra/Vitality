import AppKit
import SwiftUI

/// Owns the status item and keeps its width in step with what SwiftUI draws.
///
/// The item is `variableLength` and its length is set from the measured width
/// of the strip rather than calculated from the settings. Guessing the width
/// arithmetically means every font tweak silently clips a digit; measuring
/// means it is right by construction.
@MainActor
final class MenuBarStatusItemController {

    private let statusItem: NSStatusItem
    private let hostingView: PassthroughHostingView<MenuBarStatusView>

    /// Exposed so the app delegate can hang the click action off it.
    var button: NSStatusBarButton? { statusItem.button }
    var isVisible: Bool { statusItem.isVisible }

    init(poller: StatusPoller, settings: MenuBarSettings, history: MenuBarHistory,
         alerts: AlertCenter) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "VitalityStatusItem"
        hostingView = PassthroughHostingView(
            rootView: MenuBarStatusView(poller: poller, settings: settings,
                                        history: history, alerts: alerts)
        )

        hostingView.rootView.onWidthChange = { [weak self] width in
            self?.resize(to: width)
        }

        if let button = statusItem.button {
            // Vitality draws its own icon inside the strip, so the button's
            // built-in image would be a second, duplicate gauge.
            button.image = nil
            button.setAccessibilityLabel("Vitality")
            button.setAccessibilityHelp("Open the Vitality system monitor")
            button.toolTip = "Vitality system monitor"

            hostingView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: button.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
        }
    }

    private func resize(to width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
        let target = ceil(width)
        // Sub-pixel churn once a second would relayout the entire menu bar for
        // nothing, and drag every item to its left with it.
        guard abs(statusItem.length - target) >= 0.5 else { return }
        statusItem.length = target
    }
}

/// Feeds the strip from the live poller and reports its measured width back to
/// the controller.
struct MenuBarStatusView: View {
    @ObservedObject var poller: StatusPoller
    @ObservedObject var settings: MenuBarSettings
    @ObservedObject var history: MenuBarHistory
    @ObservedObject var alerts: AlertCenter

    var onWidthChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        MenuBarStrip(status: poller.latest, settings: settings,
                     samples: history.samples(for:),
                     alertLevel: alerts.active.first?.severity)
            .fixedSize()
            .frame(maxHeight: .infinity)
            .background(
                GeometryReader { geo in
                    Color.clear.onChange(of: geo.size.width, initial: true) { _, width in
                        onWidthChange(width)
                    }
                }
            )
            // The strip stays intentionally terse. VoiceOver receives one
            // stable summary instead of trying to interpret sparkline paths.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Vitality system monitor")
            .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let status = poller.latest else { return "Collecting system status" }
        var parts = ["Health \(status.healthScore.map(String.init) ?? "unknown")"]
        if let alert = alerts.active.first {
            parts.append("\(alert.severity.accessibilityLabel) alert: \(alert.title)")
        }
        parts.append(contentsOf: settings.displayedMetrics.map { metric in
            "\(metric.label) \(metric.reading(from: status).text)"
        })
        return parts.joined(separator: ", ")
    }
}

/// A hosting view that refuses every click so they reach the status button
/// underneath. Without this the strip looks right and does nothing: SwiftUI's
/// host swallows the mouse down, and the popover never opens.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
