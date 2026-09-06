import Foundation

enum StatusFreshness {
    enum State: Equatable {
        case live
        case stale
        case unknown
    }

    static let staleAfter: TimeInterval = 5 * 60

    /// Snapshots dated more than a minute in the future are clock errors, not
    /// live data. A 30-second skew (NTP, sleep) still counts as live.
    static let futureTolerance: TimeInterval = 60

    static func state(collectedAt: Date?, now: Date = Date()) -> State {
        guard let collectedAt else { return .unknown }
        let age = now.timeIntervalSince(collectedAt)
        if age < -futureTolerance { return .unknown }
        return age >= staleAfter ? .stale : .live
    }
}
