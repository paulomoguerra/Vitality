import Darwin
import Foundation

/// Collects every system metric Vitality shows, using only public macOS APIs.
///
/// A class rather than an enum because CPU usage is only meaningful as a delta:
/// the kernel reports cumulative ticks since boot, so a single reading tells you
/// nothing. The previous sample has to be kept between polls.
final class SystemMetrics {

    private struct TimedCache<Value> {
        let sampledAt: Date
        let value: Value
    }

    private enum CacheInterval {
        /// Volumes and their resource values are stable enough for a short
        /// cache, while still noticing mounts and meaningful free-space changes.
        static let disks: TimeInterval = 15
        /// Battery percentage and health do not change meaningfully every second.
        static let battery: TimeInterval = 15
        /// `ps` starts a child process, so keep the top-process view responsive
        /// without paying that cost on every live CPU sample.
        static let processes: TimeInterval = 3
    }

    private var previousCPUTicks: [[UInt32]]?
    private let thermalMonitor = ThermalMonitor()
    private let gpuMonitor = GPUMonitor()
    private let hardwareProvider = HardwareMetricsProvider()
    private let volumeProvider = VolumeMetricsProvider()
    private let batteryProvider = BatteryMetricsProvider()
    private let processProvider = ProcessMetricsProvider()
    private var diskCache: TimedCache<[SystemStatus.Disk]>?
    private var batteryCache: TimedCache<BatteryMetricsProvider.Snapshot>?
    private var processCache: TimedCache<ProcessMetricsProvider.Snapshot>?
    private lazy var hardware = hardwareProvider.sample()

    func collect() -> SystemStatus {
        let now = Date()
        let cpu = sampleCPU()
        let memory = sampleMemory()
        let disks = sampleDisks(now: now)
        let batterySnapshot = sampleBattery(now: now)
        let thermal = thermalMonitor.sample()
        let power = samplePower(battery: batterySnapshot.battery,
                                registry: batterySnapshot.registry)
        let processes = sampleProcesses(now: now)

        let health = HealthScore.evaluate(cpu: cpu, memory: memory,
                                          disk: disks.first(where: { $0.mount == "/" }) ?? disks.first,
                                          battery: batterySnapshot.battery)

        return SystemStatus(
            host: hardware.hostName,
            uptime: formattedUptime(),
            hardware: hardware.hardware,
            healthScore: health.score,
            healthScoreMsg: health.message,
            cpu: cpu,
            gpu: gpuMonitor.sample(),
            memory: memory,
            disks: disks,
            power: power,
            batteries: batterySnapshot.battery.map { [$0] } ?? [],
            topProcesses: processes.top,
            thermal: thermal,
            collectedAt: now
        )
    }

    // MARK: - CPU

    private func sampleCPU() -> SystemStatus.CPU {
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)

        let (overall, perCore) = sampleCPUTicks()
        let topology = hardware.cpu

        return SystemStatus.CPU(
            usage: overall,
            perCore: perCore,
            load1: loads[0], load5: loads[1], load15: loads[2],
            coreCount: topology.coreCount,
            pCoreCount: topology.pCoreCount,
            eCoreCount: topology.eCoreCount
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

        let total = hardware.totalMemoryBytes
        guard result == KERN_SUCCESS else {
            return SystemStatus.Memory(used: nil, total: total, available: nil,
                                       usedPercent: nil, swapUsed: nil, swapTotal: nil,
                                       cached: nil)
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
            cached: cached
        )
    }

    // MARK: - Disks

    private func sampleDisks(now: Date) -> [SystemStatus.Disk] {
        if let cache = diskCache,
           now.timeIntervalSince(cache.sampledAt) < CacheInterval.disks {
            return cache.value
        }

        let disks = volumeProvider.sample()

        diskCache = TimedCache(sampledAt: now, value: disks)
        return disks
    }

    // MARK: - Battery & power

    private func sampleBattery(now: Date) -> BatteryMetricsProvider.Snapshot {
        if let cache = batteryCache,
           now.timeIntervalSince(cache.sampledAt) < CacheInterval.battery {
            return cache.value
        }

        let snapshot = batteryProvider.sample()
        batteryCache = TimedCache(sampledAt: now, value: snapshot)
        return snapshot
    }

    /// Total draw and adapter input from the SMC, plus the battery's own flow.
    ///
    /// The adapter *rating* and what it is actually delivering are different
    /// numbers, and both are worth having: a 70W charger always reports 70W,
    /// while `inputWatts` says whether 8W or 60W is crossing the cable.
    private func samplePower(battery: SystemStatus.Battery?,
                             registry: [String: Any]?) -> SystemStatus.Power {
        batteryProvider.power(battery: battery,
                              registry: registry,
                              rails: thermalMonitor.power())
    }

    // MARK: - Misc

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

    private func sampleProcesses(now: Date) -> ProcessMetricsProvider.Snapshot {
        if let cache = processCache,
           now.timeIntervalSince(cache.sampledAt) < CacheInterval.processes {
            return cache.value
        }

        let snapshot = processProvider.sample()
        processCache = TimedCache(sampledAt: now, value: snapshot)
        return snapshot
    }
}
