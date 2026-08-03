import Darwin
import Foundation
import IOKit
import IOKit.ps

/// Collects every system metric Vitality shows, using only public macOS APIs.
///
/// A class rather than an enum because CPU usage is only meaningful as a delta:
/// the kernel reports cumulative ticks since boot, so a single reading tells you
/// nothing. The previous sample has to be kept between polls.
final class SystemMetrics {

    private var previousCPUTicks: [[UInt32]]?

    func collect() -> SystemStatus {
        let cpu = sampleCPU()
        let memory = sampleMemory()
        let disks = sampleDisks()
        let battery = sampleBattery()
        let power = samplePower(battery: battery)
        let processes = ProcessManager.list(limit: 5).map {
            SystemStatus.TopProcess(pid: $0.pid, name: $0.name, cpu: $0.cpu, memoryBytes: $0.memoryBytes)
        }

        let health = HealthScore.evaluate(cpu: cpu, memory: memory,
                                          disk: disks.first(where: { $0.mount == "/" }) ?? disks.first,
                                          battery: battery)

        return SystemStatus(
            host: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            uptime: formattedUptime(),
            procs: processCount(),
            hardware: sampleHardware(),
            healthScore: health.score,
            healthScoreMsg: health.message,
            cpu: cpu,
            gpu: GPUMonitor.sample(),
            memory: memory,
            disks: disks,
            power: power,
            batteries: battery.map { [$0] } ?? [],
            topProcesses: processes,
            collectedAt: Date()
        )
    }

    // MARK: - CPU

    private func sampleCPU() -> SystemStatus.CPU {
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)

        let (overall, perCore) = sampleCPUTicks()

        return SystemStatus.CPU(
            usage: overall,
            perCore: perCore,
            load1: loads[0], load5: loads[1], load15: loads[2],
            coreCount: sysctlInt("hw.logicalcpu"),
            pCoreCount: sysctlInt("hw.perflevel0.logicalcpu"),
            eCoreCount: sysctlInt("hw.perflevel1.logicalcpu")
        )
    }

    /// `host_processor_info` returns ticks accumulated since boot, so usage is
    /// the ratio of busy-to-total ticks *between two samples*. The first call
    /// after launch has no predecessor and reports zero.
    private func sampleCPUTicks() -> (Double, [Double]) {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return (0, []) }

        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }

        let states = Int(CPU_STATE_MAX)
        var current: [[UInt32]] = []
        current.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            var ticks = [UInt32](repeating: 0, count: states)
            for state in 0..<states {
                ticks[state] = UInt32(bitPattern: info[core * states + state])
            }
            current.append(ticks)
        }

        defer { previousCPUTicks = current }
        guard let previous = previousCPUTicks, previous.count == current.count else {
            return (0, Array(repeating: 0, count: current.count))
        }

        var perCore: [Double] = []
        var busyTotal = 0.0
        var allTotal = 0.0

        for (now, before) in zip(current, previous) {
            let user = Double(now[Int(CPU_STATE_USER)] &- before[Int(CPU_STATE_USER)])
            let system = Double(now[Int(CPU_STATE_SYSTEM)] &- before[Int(CPU_STATE_SYSTEM)])
            let nice = Double(now[Int(CPU_STATE_NICE)] &- before[Int(CPU_STATE_NICE)])
            let idle = Double(now[Int(CPU_STATE_IDLE)] &- before[Int(CPU_STATE_IDLE)])

            let busy = user + system + nice
            let total = busy + idle
            perCore.append(total > 0 ? busy / total * 100 : 0)
            busyTotal += busy
            allTotal += total
        }

        return (allTotal > 0 ? busyTotal / allTotal * 100 : 0, perCore)
    }

    // MARK: - Memory

    private func sampleMemory() -> SystemStatus.Memory {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let total = Int64(sysctlUInt64("hw.memsize") ?? 0)
        guard result == KERN_SUCCESS else {
            return SystemStatus.Memory(used: nil, total: total, available: nil,
                                       usedPercent: nil, swapUsed: nil, swapTotal: nil,
                                       cached: nil, pressure: nil)
        }

        let page = Int64(vm_kernel_page_size)
        // Matches how Activity Monitor frames "Memory Used": resident app pages,
        // kernel-wired pages, and whatever the compressor is holding.
        let used = (Int64(stats.active_count) + Int64(stats.wire_count)
                    + Int64(stats.compressor_page_count)) * page
        let available = (Int64(stats.free_count) + Int64(stats.inactive_count)) * page
        let cached = Int64(stats.external_page_count) * page

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let gotSwap = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0

        return SystemStatus.Memory(
            used: used,
            total: total,
            available: available,
            usedPercent: total > 0 ? Double(used) / Double(total) * 100 : nil,
            swapUsed: gotSwap ? Int64(swap.xsu_used) : nil,
            swapTotal: gotSwap ? Int64(swap.xsu_total) : nil,
            cached: cached,
            pressure: nil
        )
    }

    // MARK: - Disks

    private func sampleDisks() -> [SystemStatus.Disk] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsBrowsableKey,
        ]
        guard let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
        ) else { return [] }

        return volumes.compactMap { url -> SystemStatus.Disk? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let total = values.volumeTotalCapacity, total > 0
            else { return nil }

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
        .sorted { ($0.mount == "/" ? 0 : 1) < ($1.mount == "/" ? 0 : 1) }
    }

    // MARK: - Battery & power

    private func sampleBattery() -> SystemStatus.Battery? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int
            let max = description[kIOPSMaxCapacityKey] as? Int
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let onAC = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            let minutes = description[kIOPSTimeToEmptyKey] as? Int ?? -1
            let timeLeft = (!onAC && minutes > 0) ? "\(minutes / 60)h \(minutes % 60)m" : nil

            let registry = smartBatteryProperties()
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

            return SystemStatus.Battery(
                percent: (current != nil && max != nil && max! > 0)
                    ? Int((Double(current!) / Double(max!) * 100).rounded()) : current,
                status: onAC ? (charging ? "Charging" : "AC") : "Battery",
                timeLeft: timeLeft,
                health: description[kIOPSBatteryHealthKey] as? String,
                cycleCount: registry?["CycleCount"] as? Int,
                capacity: healthPercent
            )
        }
        return nil
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

    /// Reports adapter wattage on AC and actual battery draw on battery.
    ///
    /// Total SoC package power (what `powermetrics` shows) needs IOReport or
    /// SMC access, neither of which is public API — so Vitality reports the two
    /// figures it can measure honestly instead of guessing at a single number.
    private func samplePower(battery: SystemStatus.Battery?) -> SystemStatus.Power {
        let registry = smartBatteryProperties()
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
            isCharging: (milliamps > 0) && adapterWatts != nil,
            isOnAC: battery?.status != "Battery"
        )
    }

    // MARK: - Hardware & misc

    private func sampleHardware() -> SystemStatus.Hardware {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return SystemStatus.Hardware(
            model: marketingModelName(),
            chip: sysctlString("machdep.cpu.brand_string"),
            totalRAM: sysctlUInt64("hw.memsize").map { Int64($0) },
            osVersion: "macOS \(os.majorVersion).\(os.minorVersion)"
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

    private func formattedUptime() -> String {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return "—" }

        let seconds = Int(Date().timeIntervalSince1970) - boot.tv_sec
        guard seconds > 0 else { return "—" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func processCount() -> Int? {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&name, 4, nil, &size, nil, 0) == 0 else { return nil }
        return size / MemoryLayout<kinfo_proc>.stride
    }

    // MARK: - sysctl helpers

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
