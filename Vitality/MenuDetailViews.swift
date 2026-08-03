import SwiftUI

// MARK: - CPU

struct CPUDetailPane: View {
    let status: SystemStatus?
    let back: () -> Void

    var body: some View {
        let cpu = status?.cpu

        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "CPU", back: back)

            DetailLine(label: "Usage", value: Fmt.percent(cpu?.usage, decimals: 1))
            MiniBar(percent: cpu?.usage)
                .padding(.horizontal, 14).padding(.vertical, 5)

            if let chip = status?.hardware?.cpuModel {
                DetailLine(label: "Chip", value: chip)
            }
            DetailLine(label: "Cores",
                       value: coreSummary(cpu))

            if let perCore = cpu?.perCore, !perCore.isEmpty {
                Text("Per core")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)

                VStack(spacing: 3) {
                    ForEach(Array(perCore.enumerated()), id: \.offset) { index, value in
                        HStack(spacing: 6) {
                            Text("\(index)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 14, alignment: .trailing)
                            MiniBar(percent: value, height: 5)
                            Text(Fmt.percent(value))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
                .padding(.horizontal, 14)
            }

            Divider().padding(.vertical, 8)

            // Load average only means something relative to core count — 4.0 is
            // idle on this 10-core machine and saturated on a dual-core one.
            Text("Load average")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.bottom, 3)

            DetailLine(label: "1 min", value: loadText(cpu?.load1, cpu),
                       tint: loadTint(cpu?.load1, cpu))
            DetailLine(label: "5 min", value: loadText(cpu?.load5, cpu),
                       tint: loadTint(cpu?.load5, cpu))
            DetailLine(label: "15 min", value: loadText(cpu?.load15, cpu),
                       tint: loadTint(cpu?.load15, cpu))
        }
        .padding(.bottom, 6)
    }

    private func coreSummary(_ cpu: SystemStatus.CPU?) -> String {
        guard let total = cpu?.coreCount else { return "—" }
        if let p = cpu?.pCoreCount, let e = cpu?.eCoreCount, p + e > 0 {
            return "\(total) · \(p)P + \(e)E"
        }
        return "\(total)"
    }

    private func loadText(_ load: Double?, _ cpu: SystemStatus.CPU?) -> String {
        guard let load else { return "—" }
        guard let ratio = Fmt.loadRatio(load, cores: cpu?.coreCount) else {
            return Fmt.load(load)
        }
        return "\(Fmt.load(load))  (\(Fmt.percent(ratio)))"
    }

    private func loadTint(_ load: Double?, _ cpu: SystemStatus.CPU?) -> Color {
        Severity.forUsage(Fmt.loadRatio(load, cores: cpu?.coreCount))
    }
}

// MARK: - GPU

struct GPUDetailPane: View {
    let status: SystemStatus?
    let back: () -> Void

    var body: some View {
        let gpu = status?.measuredGPU
        let moleGPU = status?.gpu?.first

        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "GPU", back: back)

            DetailLine(label: "Utilisation", value: Fmt.percent(gpu?.utilization, decimals: 1))
            MiniBar(percent: gpu?.utilization)
                .padding(.horizontal, 14).padding(.vertical, 5)

            if let name = gpu?.name ?? moleGPU?.name {
                DetailLine(label: "Chip", value: name)
            }
            if let cores = moleGPU?.coreCount, cores > 0 {
                DetailLine(label: "Cores", value: "\(cores)")
            }

            Divider().padding(.vertical, 8)

            // Renderer vs tiler splits the work Apple's TBDR pipeline does:
            // tiler handles geometry binning, renderer shades the tiles.
            Text("Breakdown")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.bottom, 3)

            DetailLine(label: "Renderer", value: Fmt.percent(gpu?.rendererUtilization, decimals: 1))
            DetailLine(label: "Tiler", value: Fmt.percent(gpu?.tilerUtilization, decimals: 1))

            if let inUse = gpu?.inUseMemory, inUse > 0 {
                Divider().padding(.vertical, 8)
                DetailLine(label: "Memory in use", value: Fmt.bytes(inUse))
                if let allocated = gpu?.allocatedMemory, allocated > 0 {
                    DetailLine(label: "Allocated", value: Fmt.bytes(allocated))
                }
                Text("Apple silicon shares memory between CPU and GPU — this is part of your RAM, not separate VRAM.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.top, 4)
            }

            Text("Measured by Vitality via IOKit — Mole doesn't report GPU usage on Apple silicon.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.top, 8)
        }
        .padding(.bottom, 6)
    }
}

// MARK: - Memory

struct MemoryDetailPane: View {
    let status: SystemStatus?
    let back: () -> Void

    var body: some View {
        let memory = status?.memory

        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Memory", back: back)

            DetailLine(label: "Used", value: Fmt.percent(memory?.usedPercent, decimals: 1))
            MiniBar(percent: memory?.usedPercent)
                .padding(.horizontal, 14).padding(.vertical, 5)

            DetailLine(label: "In use", value: Fmt.bytes(memory?.used))
            DetailLine(label: "Available", value: Fmt.bytes(memory?.available))
            DetailLine(label: "Cached", value: Fmt.bytes(memory?.cached))
            DetailLine(label: "Total", value: Fmt.bytes(memory?.total))

            if let swapTotal = memory?.swapTotal, swapTotal > 0 {
                Divider().padding(.vertical, 8)

                let swapPercent = Double(memory?.swapUsed ?? 0) / Double(swapTotal) * 100
                DetailLine(label: "Swap used", value: Fmt.bytes(memory?.swapUsed),
                           tint: Severity.forUsage(swapPercent))
                DetailLine(label: "Swap total", value: Fmt.bytes(swapTotal))
                MiniBar(percent: swapPercent)
                    .padding(.horizontal, 14).padding(.vertical, 5)

                // Heavy swap is the signal that actually matters to a user —
                // "memory is 80% full" is normal on macOS, swapping is not.
                if swapPercent >= 50 {
                    Text("Your Mac is swapping heavily. Quitting a memory-hungry app will help.")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.top, 4)
                }
            }
        }
        .padding(.bottom, 6)
    }
}

// MARK: - Storage

struct StorageDetailPane: View {
    let status: SystemStatus?
    let back: () -> Void
    let openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Storage", back: back)

            ForEach(status?.userDisks ?? []) { disk in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(disk.mount ?? disk.device ?? "—")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1).truncationMode(.middle)
                        if disk.external == true {
                            Text("external")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(Fmt.percent(disk.usedPercent))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Severity.forUsage(disk.usedPercent))
                    }
                    MiniBar(percent: disk.usedPercent)
                    HStack {
                        Text("\(Fmt.bytes(disk.free)) free")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Fmt.bytes(disk.used)) of \(Fmt.bytes(disk.total))")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }

            if let trash = status?.trashSize, trash > 0 {
                DetailLine(label: "Trash", value: Fmt.bytes(trash))
            }

            Divider().padding(.vertical, 8)
            MenuActionRow(icon: "folder.badge.gearshape",
                          label: "Manage storage…", action: openDashboard)
        }
        .padding(.bottom, 6)
    }
}

// MARK: - Power & battery

struct PowerDetailPane: View {
    let status: SystemStatus?
    let back: () -> Void

    var body: some View {
        let thermal = status?.thermal
        let battery = status?.battery

        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Power", back: back)

            DetailLine(label: "System draw", value: Fmt.watts(thermal?.systemPower))
            if let adapter = thermal?.adapterPower, adapter > 0 {
                DetailLine(label: "Adapter", value: Fmt.watts(adapter))
            }
            if let fan = thermal?.fanSpeed, fan > 0 {
                DetailLine(label: "Fan", value: "\(fan) rpm")
            }
            if let temp = thermal?.cpuTemp, temp > 0 {
                DetailLine(label: "CPU temp", value: String(format: "%.0f°C", temp))
            }

            if let battery {
                Divider().padding(.vertical, 8)
                Text("Battery")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.bottom, 3)

                DetailLine(label: "Charge", value: battery.percent.map { "\($0)%" } ?? "—")
                MiniBar(percent: battery.percent.map(Double.init))
                    .padding(.horizontal, 14).padding(.vertical, 5)

                DetailLine(label: "Status", value: battery.status ?? "—")
                if let timeLeft = battery.timeLeft, !timeLeft.isEmpty {
                    DetailLine(label: "Time left", value: timeLeft)
                }
                if let health = battery.health {
                    DetailLine(label: "Health", value: health)
                }
                if let capacity = battery.capacity, capacity > 0 {
                    // Maximum capacity relative to when the battery was new —
                    // Apple considers a battery worth replacing below 80%.
                    DetailLine(label: "Max capacity", value: "\(capacity)%",
                               tint: capacity < 80 ? .orange : .primary)
                }
                if let cycles = battery.cycleCount, cycles > 0 {
                    DetailLine(label: "Cycles", value: "\(cycles)")
                }
            }
        }
        .padding(.bottom, 6)
    }
}

// MARK: - Processes

struct ProcessesDetailPane: View {
    let status: SystemStatus?
    let back: () -> Void
    let openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Top processes", back: back)

            if status?.processes.isEmpty ?? true {
                Text("No process data.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 6)
            } else {
                ForEach(status?.processes ?? []) { process in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(process.name ?? "—")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text(Fmt.percent(process.cpu, decimals: 1))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Severity.forUsage(process.cpu))
                        }
                        HStack {
                            Text("PID \(process.pid.map(String.init) ?? "—")")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(Fmt.bytes(process.memoryBytes))
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
            }

            Divider().padding(.vertical, 8)
            MenuActionRow(icon: "xmark.circle",
                          label: "Manage processes…", action: openDashboard)
        }
        .padding(.bottom, 6)
    }
}
