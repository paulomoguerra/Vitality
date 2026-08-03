import Foundation

struct SystemStatus: Codable {
    struct CPU: Codable {
        let usage: Double
        let coreCount: Int
        let pCoreCount: Int
        let eCoreCount: Int

        enum CodingKeys: String, CodingKey {
            case usage
            case coreCount = "core_count"
            case pCoreCount = "p_core_count"
            case eCoreCount = "e_core_count"
        }
    }

    struct Memory: Codable {
        let used: Int64
        let total: Int64
        let usedPercent: Double

        enum CodingKeys: String, CodingKey {
            case used, total
            case usedPercent = "used_percent"
        }
    }

    struct Disk: Codable {
        let mount: String
        let used: Int64
        let total: Int64
        let usedPercent: Double

        enum CodingKeys: String, CodingKey {
            case mount, used, total
            case usedPercent = "used_percent"
        }
    }

    struct Thermal: Codable {
        let systemPower: Double
        let adapterPower: Double

        enum CodingKeys: String, CodingKey {
            case systemPower = "system_power"
            case adapterPower = "adapter_power"
        }
    }

    struct Battery: Codable {
        let percent: Int
        let status: String
    }

    struct TopProcess: Codable {
        let name: String
        let cpu: Double
    }

    let host: String
    let healthScore: Int
    let healthScoreMsg: String
    let cpu: CPU
    let memory: Memory
    let disks: [Disk]
    let thermal: Thermal
    let batteries: [Battery]
    let topProcesses: [TopProcess]
    let collectedAt: String

    enum CodingKeys: String, CodingKey {
        case host, cpu, memory, disks, thermal, batteries
        case healthScore = "health_score"
        case healthScoreMsg = "health_score_msg"
        case topProcesses = "top_processes"
        case collectedAt = "collected_at"
    }

    var primaryDisk: Disk? {
        disks.first(where: { $0.mount == "/" }) ?? disks.first
    }

    var battery: Battery? { batteries.first }
    var topProcess: TopProcess? { topProcesses.first }
}
