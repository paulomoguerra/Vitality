import Combine
import Foundation

/// A short rolling window of every menu bar metric, so the chips can draw a
/// sparkline instead of just a number.
///
/// Kept separate from `StatusPoller`: the poller's job is the current truth of
/// the machine, and it already writes that to the shared store for the widgets.
/// History is purely a presentation concern for one surface, and it should not
/// grow into something the widget extension has to decode.
@MainActor
final class MenuBarHistory: ObservableObject {

    /// 40 samples at the poller's 1 Hz is 40 seconds — enough to see a spike
    /// arrive and decay across a chip barely 24pt wide.
    static let capacity = 40

    @Published private(set) var samples: [MenuBarMetric: [Double]] = [:]

    private var cancellable: AnyCancellable?

    init(poller: StatusPoller) {
        cancellable = poller.$latest.sink { [weak self] status in
            self?.record(status)
        }
    }

    func samples(for metric: MenuBarMetric) -> [Double] {
        samples[metric] ?? []
    }

    private func record(_ status: SystemStatus?) {
        guard let status else { return }
        for metric in MenuBarMetric.allCases {
            guard let sample = metric.reading(from: status).sample else { continue }
            var window = samples[metric] ?? []
            window.append(sample)
            if window.count > Self.capacity {
                window.removeFirst(window.count - Self.capacity)
            }
            samples[metric] = window
        }
    }
}
