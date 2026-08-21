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

    /// Power figures Vitality can measure.
    ///
    /// `systemWatts` and `inputWatts` come from the SMC's own rails — see
    /// `SMC` for why that source is used and what it costs. `adapterWatts` is
    /// the adapter's *rating* from IOKit, which is a different thing from what
    /// it is actually delivering: a 70W charger reads 70W whether the Mac is
    /// drawing 8W or 60W from it.
    struct Power: Codable {
        /// What the adapter is rated for, not what it is supplying.
        let adapterWatts: Double?
        let batteryWatts: Double?
        /// Everything the machine is consuming right now (SMC `PSTR`).
        let systemWatts: Double?
        /// What is actually coming in over the cable (SMC `PDTR`).
        let inputWatts: Double?
        let isCharging: Bool?
        let isOnAC: Bool?
    }

    /// Die and component temperatures, in Celsius.
    ///
    /// Every field is optional: a Mac that exposes no sensors gets no thermal
    /// section rather than a screen of dashes.
    struct Thermal: Codable {
        struct Sensor: Codable, Identifiable {
            /// The raw SMC key, e.g. `Tp0f` — kept so a reading can always be
            /// traced back to its source.
            let key: String
            let label: String
            let celsius: Double
            /// False when Vitality knows the reading is real but not what it
            /// measures. Those are shown, and shown as unknown.
            let isIdentified: Bool

            var id: String { key }
        }

        /// Mean across every core sensor, performance and efficiency together.
        let cpu: Double?
        let performanceCores: Double?
        let efficiencyCores: Double?
        let gpu: Double?
        let battery: Double?
        let storage: Double?
        let enclosure: Double?
        /// The hottest named sensor on the machine.
        let hottest: Sensor?
        let sensors: [Sensor]
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
    let thermal: Thermal?
    let collectedAt: Date?

    // MARK: - Convenience

    var primaryDisk: Disk? {
        disks?.first(where: { $0.mount == "/" }) ?? disks?.first
    }

    var userDisks: [Disk] { disks ?? [] }
    var battery: Battery? { batteries?.first }
    var topProcess: TopProcess? { topProcesses?.first }
    var processes: [TopProcess] { topProcesses ?? [] }

    /// The headline power figure: what the machine is actually consuming.
    ///
    /// Falls back to the adapter rating / battery flow pair on a Mac whose SMC
    /// gives nothing, which is worse but still true.
    var headlinePower: Double? {
        if let systemWatts = power?.systemWatts { return systemWatts }
        if power?.isOnAC == true { return power?.adapterWatts ?? power?.batteryWatts }
        return power?.batteryWatts
    }

    var headlinePowerLabel: String {
        if power?.systemWatts != nil { return "Power draw" }
        return power?.isOnAC == true ? "Adapter" : "Battery draw"
    }
}
