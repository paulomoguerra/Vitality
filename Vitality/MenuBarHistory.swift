import Combine
import Foundation

/// A short rolling window of every menu bar metric that is currently on screen,
/// so the chips can draw a sparkline instead of just a number.
///
/// Kept separate from `StatusPoller`: the poller's job is the current truth of
/// the machine, and it already writes that to the shared store for the widgets.
/// History is purely a presentation concern for one surface, and it should not
/// grow into something the widget extension has to decode.
///
/// It tracks only the metrics on screen. Most people show two or three chips,
/// so keeping a window for all ten was work nothing could read.
///
/// It deliberately does *not* also wait for the graph to be switched on. The
/// settings pane previews the strip live, and a window that only starts filling
/// at the moment the toggle flips would show 40 seconds of nothing in the one
/// place built to show what the setting does.
@MainActor
final class MenuBarHistory: ObservableObject {

    /// 40 samples at the poller's 1 Hz is 40 seconds — enough to see a spike
    /// arrive and decay across a chip barely 24pt wide.
    static let capacity = 40

    private let settings: MenuBarSettings
    private var storage: [MenuBarMetric: [Double]] = [:]
    private var cancellable: AnyCancellable?

    init(poller: StatusPoller, settings: MenuBarSettings) {
        self.settings = settings
        cancellable = poller.$latest.sink { [weak self] status in
            self?.record(status)
        }
    }

    func samples(for metric: MenuBarMetric) -> [Double] {
        storage[metric] ?? []
    }

    private func record(_ status: SystemStatus?) {
        guard let status else { return }

        let tracked = Set(settings.displayedMetrics.filter(\.isGraphable))
        var changed = false

        // A metric that was switched off keeps a stale 40-second window
        // otherwise, and shows it the instant it is switched back on.
        //
        // The keys are collected before anything is removed: `storage.keys` is
        // a view onto the dictionary, and mutating it mid-iteration is an
        // exclusivity violation that traps at runtime rather than a compile
        // error.
        let stale = storage.keys.filter { !tracked.contains($0) }
        for metric in stale {
            storage.removeValue(forKey: metric)
            changed = true
        }

        for metric in tracked {
            guard let sample = metric.reading(from: status).sample else { continue }
            var window = storage[metric] ?? []
            window.append(sample)
            // Exactly one sample lands per poll, so the window can only ever be
            // one over.
            if window.count > Self.capacity { window.removeFirst(window.count - Self.capacity) }
            storage[metric] = window
            changed = true
        }

        // One notification per poll rather than one per metric: the strip is
        // redrawn as a whole either way.
        if changed { objectWillChange.send() }
    }
}
