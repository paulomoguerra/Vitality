import Foundation

@MainActor
final class StatusPoller: ObservableObject {
    @Published private(set) var latest: SystemStatus?

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        Task.detached(priority: .utility) {
            guard let status = StatusCollector.collect() else { return }
            SharedStatusStore.write(status)
            await MainActor.run { [weak self] in
                self?.latest = status
            }
        }
    }
}
