import Combine
import Foundation

/// Five-minute history for the dashboard. It is deliberately separate from
/// menu-bar history: the dashboard can keep a wider, more useful view without
/// changing widget payloads. Owned by `DashboardWindowController` rather than
/// the view tree, so it records for the whole session and the charts are full
/// the moment the window opens — even after the window itself was torn down.
@MainActor
final class DashboardHistory: ObservableObject {

    struct Snapshot {
        let cpu: Double?
        let gpu: Double?
        let memory: Double?
        let disk: Double?
        let power: Double?
        let collectedAt: Date?
    }

    static let capacity = 300

    @Published private(set) var samples: [Snapshot] = []
    private var cancellable: AnyCancellable?

    init(poller: StatusPoller) {
        cancellable = poller.$latest.sink { [weak self] status in
            self?.record(status)
        }
    }

    func values(_ keyPath: KeyPath<Snapshot, Double?>) -> [Double] {
        samples.compactMap { $0[keyPath: keyPath] }
    }

    func average(_ keyPath: KeyPath<Snapshot, Double?>, last count: Int = 30) -> Double? {
        let recent = samples.suffix(count).compactMap { $0[keyPath: keyPath] }
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0, +) / Double(recent.count)
    }

    private func record(_ status: SystemStatus?) {
        guard let status else { return }
        samples.append(Snapshot(
            cpu: status.cpu?.usage,
            gpu: status.gpu?.utilization,
            memory: status.memory?.usedPercent,
            disk: status.primaryDisk?.usedPercent,
            power: status.headlinePower,
            collectedAt: status.collectedAt
        ))
        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
    }
}
