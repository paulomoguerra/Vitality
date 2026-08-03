import Foundation

/// GPU figures read from IOKit's `IOAccelerator` registry.
struct GPUStats: Codable, Equatable {
    let name: String?
    /// Overall device utilisation, 0–100.
    let utilization: Double?
    let rendererUtilization: Double?
    let tilerUtilization: Double?
    let inUseMemory: Int64?
    let allocatedMemory: Int64?

    enum CodingKeys: String, CodingKey {
        case name, utilization
        case rendererUtilization = "renderer_utilization"
        case tilerUtilization = "tiler_utilization"
        case inUseMemory = "in_use_memory"
        case allocatedMemory = "allocated_memory"
    }
}

/// A snapshot of the machine, measured entirely through public macOS APIs.
///
/// Fields stay optional even though Vitality produces them itself: the app and
/// the widget extension are separate binaries that can be running different
/// builds after an update, and one unknown key must never blank the whole UI.
struct SystemStatus: Codable {

    struct Hardware: Codable {
        let model: String?      // "MacBook Air"
        let chip: String?       // "Apple M4"
        let totalRAM: Int64?
        let osVersion: String?
    }

    struct CPU: Codable {
        let usage: Double?
        let perCore: [Double]?
        let load1: Double?
        let load5: Double?
        let load15: Double?
        let coreCount: Int?
        let pCoreCount: Int?
        let eCoreCount: Int?
    }

    struct Memory: Codable {
        let used: Int64?
        let total: Int64?
        let available: Int64?
        let usedPercent: Double?
        let swapUsed: Int64?
        let swapTotal: Int64?
        let cached: Int64?
        let pressure: String?
    }

    struct Disk: Codable, Identifiable {
        let mount: String?
        let name: String?
        let used: Int64?
        let total: Int64?
        let usedPercent: Double?
        let isInternal: Bool?
        let isRemovable: Bool?

        var id: String { mount ?? name ?? UUID().uuidString }
        var free: Int64 { max(0, (total ?? 0) - (used ?? 0)) }

        /// "Macintosh HD" beats a bare "/", and a volume name beats a long path.
        var displayName: String {
            if let name, !name.isEmpty { return name }
            guard let mount else { return "—" }
            return mount == "/" ? "Startup disk" : (mount as NSString).lastPathComponent
        }
    }

    /// Power figures Vitality can measure honestly.
    ///
    /// Total SoC package draw — the single wattage `powermetrics` reports —
    /// requires IOReport or SMC access, neither of which is public API. Rather
    /// than invent one number, Vitality reports adapter wattage and actual
    /// battery flow, which are both real and both measurable.
    struct Power: Codable {
        let adapterWatts: Double?
        let batteryWatts: Double?
        let isCharging: Bool?
        let isOnAC: Bool?
    }

    struct Battery: Codable {
        let percent: Int?
        let status: String?
        let timeLeft: String?
        let health: String?
        let cycleCount: Int?
        /// Maximum capacity relative to new, as a percentage.
        let capacity: Int?
    }

    struct TopProcess: Codable, Identifiable {
        let pid: Int32?
        let name: String?
        let cpu: Double?
        let memoryBytes: Int64?

        var id: Int32 { pid ?? -1 }
    }

    let host: String?
    let uptime: String?
    let procs: Int?
    let hardware: Hardware?
    let healthScore: Int?
    let healthScoreMsg: String?
    let cpu: CPU?
    let gpu: GPUStats?
    let memory: Memory?
    let disks: [Disk]?
    let power: Power?
    let batteries: [Battery]?
    let topProcesses: [TopProcess]?
    let collectedAt: Date?

    // MARK: - Convenience

    var primaryDisk: Disk? {
        disks?.first(where: { $0.mount == "/" }) ?? disks?.first
    }

    var userDisks: [Disk] { disks ?? [] }
    var battery: Battery? { batteries?.first }
    var topProcess: TopProcess? { topProcesses?.first }
    var processes: [TopProcess] { topProcesses ?? [] }

    /// The headline power figure: what the adapter is supplying when plugged in,
    /// or what the battery is actually giving up when it isn't.
    var headlinePower: Double? {
        if power?.isOnAC == true { return power?.adapterWatts ?? power?.batteryWatts }
        return power?.batteryWatts
    }

    var headlinePowerLabel: String {
        power?.isOnAC == true ? "Adapter" : "Battery draw"
    }
}
