import Foundation

/// GPU figures Vitality measures itself through IOKit.
///
/// Kept separate from `SystemStatus.GPU` (which mirrors Mole's payload) because
/// the two have different provenance: Mole's `gpu[].usage` is `-1` on Apple
/// silicon, while these come from the IOAccelerator registry and are real.
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

/// Decoded from `mo status --json`.
///
/// Every field is optional on purpose. Mole is a separate project on its own
/// release cadence, and a single renamed or dropped key would otherwise make
/// `JSONDecoder` throw for the *whole* payload — which surfaces to the user as
/// a blank menu bar and blank widgets with no explanation. Tolerating partial
/// data means a Mole update can degrade one row instead of the entire app.
struct SystemStatus: Codable {

    struct Hardware: Codable {
        let model: String?
        let cpuModel: String?
        let totalRam: String?
        let diskSize: String?
        let osVersion: String?

        enum CodingKeys: String, CodingKey {
            case model
            case cpuModel = "cpu_model"
            case totalRam = "total_ram"
            case diskSize = "disk_size"
            case osVersion = "os_version"
        }
    }

    struct CPU: Codable {
        let usage: Double?
        let perCore: [Double]?
        let load1: Double?
        let load5: Double?
        let load15: Double?
        let coreCount: Int?
        let logicalCPU: Int?
        let pCoreCount: Int?
        let eCoreCount: Int?

        enum CodingKeys: String, CodingKey {
            case usage, load1, load5, load15
            case perCore = "per_core"
            case coreCount = "core_count"
            case logicalCPU = "logical_cpu"
            case pCoreCount = "p_core_count"
            case eCoreCount = "e_core_count"
        }
    }

    struct GPU: Codable {
        let name: String?
        let usage: Double?
        let coreCount: Int?

        enum CodingKeys: String, CodingKey {
            case name, usage
            case coreCount = "core_count"
        }
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

        enum CodingKeys: String, CodingKey {
            case used, total, available, cached, pressure
            case usedPercent = "used_percent"
            case swapUsed = "swap_used"
            case swapTotal = "swap_total"
        }
    }

    struct Disk: Codable, Identifiable {
        let mount: String?
        let device: String?
        let used: Int64?
        let total: Int64?
        let usedPercent: Double?
        let fstype: String?
        let external: Bool?
        let smartStatus: String?

        var id: String { (mount ?? "") + "|" + (device ?? "") }
        var free: Int64 { max(0, (total ?? 0) - (used ?? 0)) }

        enum CodingKeys: String, CodingKey {
            case mount, device, used, total, fstype, external
            case usedPercent = "used_percent"
            case smartStatus = "smart_status"
        }
    }

    struct Thermal: Codable {
        let cpuTemp: Double?
        let fanSpeed: Int?
        let fanCount: Int?
        let systemPower: Double?
        let adapterPower: Double?
        let batteryPower: Double?

        enum CodingKeys: String, CodingKey {
            case cpuTemp = "cpu_temp"
            case fanSpeed = "fan_speed"
            case fanCount = "fan_count"
            case systemPower = "system_power"
            case adapterPower = "adapter_power"
            case batteryPower = "battery_power"
        }
    }

    struct Battery: Codable {
        let percent: Int?
        let status: String?
        let timeLeft: String?
        let health: String?
        let cycleCount: Int?
        let capacity: Int?

        enum CodingKeys: String, CodingKey {
            case percent, status, health, capacity
            case timeLeft = "time_left"
            case cycleCount = "cycle_count"
        }
    }

    struct TopProcess: Codable, Identifiable {
        let pid: Int32?
        let ppid: Int32?
        let name: String?
        let command: String?
        let cpu: Double?
        let memory: Double?
        let memoryBytes: Int64?

        var id: Int32 { pid ?? -1 }

        enum CodingKeys: String, CodingKey {
            case pid, ppid, name, command, cpu, memory
            case memoryBytes = "memory_bytes"
        }
    }

    /// GPU figures Vitality measures itself via IOKit.
    ///
    /// Not part of Mole's payload — Mole reports `usage: -1` on Apple silicon,
    /// so this is absent when decoding `mo status --json` and is filled in by
    /// the app before the snapshot is written to the shared container. `var`
    /// rather than `let` precisely so the poller can attach it.
    var measuredGPU: GPUStats?

    let host: String?
    let platform: String?
    let uptime: String?
    let procs: Int?
    let hardware: Hardware?
    let healthScore: Int?
    let healthScoreMsg: String?
    let cpu: CPU?
    let gpu: [GPU]?
    let memory: Memory?
    let disks: [Disk]?
    let trashSize: Int64?
    let thermal: Thermal?
    let batteries: [Battery]?
    let topProcesses: [TopProcess]?
    let collectedAt: String?

    enum CodingKeys: String, CodingKey {
        case host, platform, uptime, procs, hardware, cpu, gpu, memory, disks, thermal, batteries
        case measuredGPU = "measured_gpu"
        case healthScore = "health_score"
        case healthScoreMsg = "health_score_msg"
        case trashSize = "trash_size"
        case topProcesses = "top_processes"
        case collectedAt = "collected_at"
    }

    /// The boot volume, falling back to whatever disk Mole listed first.
    var primaryDisk: Disk? {
        disks?.first(where: { $0.mount == "/" }) ?? disks?.first
    }

    /// Disks worth showing. Zero-sized entries are placeholders Mole emits for
    /// volumes it could not stat, and they'd render as empty rows.
    var userDisks: [Disk] {
        (disks ?? []).filter { ($0.total ?? 0) > 0 }
    }

    var battery: Battery? { batteries?.first }
    var topProcess: TopProcess? { topProcesses?.first }
    var processes: [TopProcess] { topProcesses ?? [] }
}
