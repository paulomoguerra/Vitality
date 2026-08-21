import Darwin
import Foundation
import IOKit
import IOKit.ps

/// Reads machine identity and topology, which are stable for the lifetime of
/// a metrics engine.
struct HardwareMetricsProvider {

    struct CPUProfile {
        let coreCount: Int?
        let pCoreCount: Int?
        let eCoreCount: Int?
    }

    struct Snapshot {
        let hostName: String
        let totalMemoryBytes: Int64
        let cpu: CPUProfile
        let hardware: SystemStatus.Hardware
    }

    func sample() -> Snapshot {
        let hostName = Host.current().localizedName
            ?? ProcessInfo.processInfo.hostName
        let totalMemoryBytes = Int64(sysctlUInt64("hw.memsize") ?? 0)
        let cpu = CPUProfile(
            coreCount: sysctlInt("hw.logicalcpu"),
            pCoreCount: sysctlInt("hw.perflevel0.logicalcpu"),
            eCoreCount: sysctlInt("hw.perflevel1.logicalcpu")
        )
        let os = ProcessInfo.processInfo.operatingSystemVersion

        return Snapshot(
            hostName: hostName,
            totalMemoryBytes: totalMemoryBytes,
            cpu: cpu,
            hardware: SystemStatus.Hardware(
                model: marketingModelName(),
                chip: sysctlString("machdep.cpu.brand_string"),
                totalRAM: totalMemoryBytes > 0 ? totalMemoryBytes : nil,
                osVersion: "macOS \(os.majorVersion).\(os.minorVersion)"
            )
        )
    }

    /// `hw.model` gives identifiers like "Mac16,12".
    ///
    /// The human-readable name lives on the device tree's `/product` node —
    /// **not** on `IOPlatformExpertDevice`, which only carries the identifier.
    /// The full value is like "MacBook Air (13-inch, M4, 2025)"; the trailing
    /// parenthetical is dropped because the chip and RAM are shown alongside it
    /// anyway, and the long form truncates badly in the widget.
    private func marketingModelName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return sysctlString("hw.model") }
        defer { IOObjectRelease(entry) }

        if let data = IORegistryEntryCreateCFProperty(
            entry, "product-name" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Data {
            let full = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let short = full.components(separatedBy: " (").first ?? full
            if !short.isEmpty { return short }
        }
        return sysctlString("hw.model")
    }

    private func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    private func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Reads mounted volumes and converts their resource values to dashboard disks.
struct VolumeMetricsProvider {

    private let resourceKeys: [URLResourceKey] = [
        .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsBrowsableKey,
    ]

    func sample() -> [SystemStatus.Disk] {
        guard let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: resourceKeys, options: [.skipHiddenVolumes]
        ) else { return [] }

        return volumes.compactMap { url -> SystemStatus.Disk? in
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else {
                return nil
            }
            return Self.disk(for: url, values: values)
        }
        .sorted { ($0.mount == "/" ? 0 : 1) < ($1.mount == "/" ? 0 : 1) }
    }

    /// Kept as a pure conversion boundary so volume filtering and arithmetic
    /// can be tested without mounting or unmounting anything.
    static func disk(for url: URL, values: URLResourceValues) -> SystemStatus.Disk? {
        guard let total = values.volumeTotalCapacity, total > 0 else { return nil }

        // Xcode's simulator runtimes mount as browsable volumes and are
        // permanently near-full. They're Xcode's business, not the user's.
        if url.path.contains("/CoreSimulator/Volumes/") { return nil }

        let available = Int64(values.volumeAvailableCapacity ?? 0)
        let capacity = Int64(total)
        let used = max(0, capacity - available)

        return SystemStatus.Disk(
            mount: url.path,
            name: values.volumeName,
            used: used,
            total: capacity,
            usedPercent: Double(used) / Double(capacity) * 100,
            isInternal: values.volumeIsInternal ?? true,
            isRemovable: values.volumeIsRemovable ?? false
        )
    }
}

/// Reads the power-source registry and assembles battery/power snapshots.
struct BatteryMetricsProvider {

    struct Snapshot {
        let battery: SystemStatus.Battery?
        let registry: [String: Any]?
    }

    func sample() -> Snapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return Snapshot(battery: nil, registry: nil) }

        // The registry lookup is comparatively expensive and is shared by the
        // battery and power snapshots for this cache period.
        let registry = smartBatteryProperties()

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int
            let max = description[kIOPSMaxCapacityKey] as? Int
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let onAC = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            let minutes = description[kIOPSTimeToEmptyKey] as? Int ?? -1
            let timeLeft = (!onAC && minutes > 0) ? "\(minutes / 60)h \(minutes % 60)m" : nil

            // These live inside a nested "BatteryData" dictionary. The
            // top-level "MaxCapacity" is a normalised figure that reads 100 on
            // modern macOS regardless of wear, so it's useless as a health
            // signal.
            let batteryData = registry?["BatteryData"] as? [String: Any]
            let designCapacity = batteryData?["DesignCapacity"] as? Int
            let nominalCapacity = batteryData?["NominalChargeCapacity"] as? Int
            let healthPercent: Int? = {
                guard let designCapacity, let nominalCapacity, designCapacity > 0 else { return nil }
                return Int((Double(nominalCapacity) / Double(designCapacity) * 100).rounded())
            }()

            let battery = SystemStatus.Battery(
                percent: (current != nil && max != nil && max! > 0)
                    ? Int((Double(current!) / Double(max!) * 100).rounded()) : current,
                status: onAC ? (charging ? "Charging" : "AC") : "Battery",
                timeLeft: timeLeft,
                health: description[kIOPSBatteryHealthKey] as? String,
                cycleCount: registry?["CycleCount"] as? Int,
                capacity: healthPercent
            )

            return Snapshot(battery: battery, registry: registry)
        }
        return Snapshot(battery: nil, registry: registry)
    }

    /// Total draw and adapter input from the SMC, plus the battery's own flow.
    ///
    /// The adapter *rating* and what it is actually delivering are different
    /// numbers, and both are worth having: a 70W charger always reports 70W,
    /// while `inputWatts` says whether 8W or 60W is crossing the cable.
    func power(battery: SystemStatus.Battery?,
               registry: [String: Any]?,
               rails: (system: Double?, input: Double?)) -> SystemStatus.Power {
        let millivolts = registry?["Voltage"] as? Int ?? 0
        let milliamps = registry?["InstantAmperage"] as? Int
            ?? registry?["Amperage"] as? Int ?? 0

        // Amperage is signed: negative while discharging.
        let batteryWatts = abs(Double(millivolts) * Double(milliamps)) / 1_000_000

        var adapterWatts: Double?
        if let adapter = registry?["AdapterDetails"] as? [String: Any],
           let watts = adapter["Watts"] as? Int, watts > 0 {
            adapterWatts = Double(watts)
        }

        return SystemStatus.Power(
            adapterWatts: adapterWatts,
            batteryWatts: batteryWatts > 0 ? batteryWatts : nil,
            systemWatts: rails.system,
            inputWatts: rails.input,
            isCharging: (milliamps > 0) && adapterWatts != nil,
            isOnAC: battery?.status != "Battery"
        )
    }

    /// Cycle count and design capacity aren't exposed through IOPowerSources —
    /// they only live on the raw AppleSmartBattery registry node.
    private func smartBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS
        else { return nil }
        return unmanaged?.takeRetainedValue() as? [String: Any]
    }
}

/// Reads the compact top-process view used by status.
struct ProcessMetricsProvider {

    struct Snapshot {
        let top: [SystemStatus.TopProcess]
    }

    func sample() -> Snapshot {
        let top = ProcessManager.list(limit: 5).map {
            SystemStatus.TopProcess(pid: $0.pid, name: $0.name, cpu: $0.cpu, memoryBytes: $0.memoryBytes)
        }
        return Snapshot(top: top)
    }
}
