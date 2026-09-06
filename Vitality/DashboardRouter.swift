import Combine

@MainActor
final class DashboardRouter: ObservableObject {
    @Published var section: DashboardSection = .overview {
        didSet {
            // Alert routing stashes a mode on Storage/Activity. Leaving that
            // destination has to drop it, or the next sidebar tap reopens the
            // leftover Free-up / memory-sort view instead of the default.
            if section != .storage { storageMode = .cleanup }
            if section != .activity {
                processSort = .cpu
                activityMode = .processes
            }
        }
    }
    @Published var storageMode: StorageMode = .cleanup
    @Published var processSort: ProcessSort = .cpu
    @Published var activityMode: ActivityMode = .processes

    func open(_ section: DashboardSection) {
        self.section = section
    }

    func open(alert rule: AlertRuleID) {
        if rule == .diskFull {
            storageMode = .cleanup
        }
        if rule == .swapHeavy {
            processSort = .memory
            activityMode = .processes
        } else if rule == .cpuSustained {
            processSort = .cpu
            activityMode = .processes
        }
        if let destination = rule.dashboardSection {
            section = destination
        }
    }
}

extension AlertRuleID {
    var dashboardSection: DashboardSection? {
        switch self {
        case .diskFull:     return .storage
        case .cpuSustained: return .activity
        case .swapHeavy:    return .activity
        case .tempHigh:     return .sensors
        case .batteryLow:   return .power
        }
    }
}
