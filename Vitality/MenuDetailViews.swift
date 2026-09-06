import SwiftUI

// MARK: - Shared detail chrome

private enum MenuDetailMetrics {
    static let horizontalPadding: CGFloat = 14
    static let rowMinHeight: CGFloat = 32
    static let actionMinHeight: CGFloat = 40
    static let insetRadius: CGFloat = 8
}

/// The detail panes share one small card so the popover reads as a deliberate
/// surface rather than a stack of unrelated rows. The 8pt outer inset leaves
/// room for the 12pt card radius and keeps nested corners concentric.
private struct MenuDetailSurface<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .background(ThemeCardBackground(radius: Theme.nestedRadius))
            .padding(.horizontal, 8)
    }
}

private struct MenuDetailHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        Button(action: back) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                Text(title)
                    .font(Theme.instrument(11, .medium))
                    .tracking(1.4)
                    .foregroundStyle(Theme.ink)
                    .textCase(.uppercase)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, MenuDetailMetrics.horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: MenuDetailMetrics.actionMinHeight,
                   alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Back to overview, " + title))
        .accessibilityHint(Text("Returns to the system overview"))
        .help("Back to overview")
    }
}

private struct MenuDetailSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.instrument(10, .medium))
            .tracking(1.3)
            .foregroundStyle(Theme.inkSecondary)
            .textCase(.uppercase)
            .padding(.horizontal, MenuDetailMetrics.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

private struct MenuDetailDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
            .padding(.horizontal, MenuDetailMetrics.horizontalPadding)
            .padding(.vertical, 8)
            .accessibilityHidden(true)
    }
}

private struct MenuDetailLine: View {
    let label: String
    let value: String
    var tint: Color = Theme.ink
    var status: Severity.Level?
    var accessibilityValueText: String?

    init(label: String, value: String, tint: Color = Theme.ink,
         status: Severity.Level? = nil, accessibilityValueText: String? = nil) {
        self.label = label
        self.value = value
        self.tint = tint
        self.status = status
        self.accessibilityValueText = accessibilityValueText
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Theme.instrument(10))
                .tracking(0.8)
                .foregroundStyle(Theme.inkSecondary)
                .textCase(.uppercase)
                .lineLimit(1)

            Spacer(minLength: 10)

            if let status {
                MenuDetailStatusMark(status: status)
            }

            Text(value)
                .font(Theme.mono(11, .medium))
                .foregroundStyle(value == "—" ? Theme.inkTertiary : tint)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
        }
        .padding(.horizontal, MenuDetailMetrics.horizontalPadding)
        .padding(.vertical, 4)
        .frame(minHeight: MenuDetailMetrics.rowMinHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spokenValue))
    }

    private var spokenValue: String {
        let base = accessibilityValueText ?? menuSpokenValue(value)
        guard let status else { return base }
        return base + ", " + status.accessibilityLabel
    }
}

private struct MenuDetailStatusMark: View {
    let status: Severity.Level

    var body: some View {
        Image(systemName: status.symbolName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(status.color)
            .accessibilityHidden(true)
    }
}

/// A meter with an explicit status colour. `MiniBar` is intentionally kept
/// unchanged for the dashboard; detail panes need charge and temperature to
/// use their own semantics instead of treating every value as usage.
private struct MenuDetailBar: View {
    let percent: Double?
    let label: String
    var status: Severity.Level?
    var valueText: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.progressTrack)

                if let percent {
                    Capsule()
                        .fill(status?.color ?? Theme.inkSecondary)
                        .frame(width: geometry.size.width * CGFloat(min(max(percent, 0), 100) / 100))
                }
            }
        }
        .frame(height: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(valueText ?? menuSpokenValue(Fmt.percent(percent))))
    }
}

private struct MenuDetailInset<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: MenuDetailMetrics.insetRadius, style: .continuous)
                    .fill(Theme.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MenuDetailMetrics.insetRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: MenuDetailMetrics.insetRadius, style: .continuous))
            .padding(.horizontal, 10)
    }
}

private struct MenuDetailNote: View {
    let text: String
    var icon: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .accessibilityHidden(true)
            }

            Text(text)
                .font(Theme.body(10))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, MenuDetailMetrics.horizontalPadding)
        .padding(.top, 6)
    }
}

private struct MenuDetailEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 26, height: 26)
                    .background(Theme.chipFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.body(12, .medium))
                        .foregroundStyle(Theme.ink)
                    Text(message)
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                }
                .buttonStyle(ThemePillButtonStyle(prominent: true))
                .frame(minHeight: MenuDetailMetrics.actionMinHeight, alignment: .leading)
                .accessibilityHint(Text("Try this recovery action"))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: MenuDetailMetrics.insetRadius, style: .continuous)
                .fill(Theme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MenuDetailMetrics.insetRadius, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: MenuDetailMetrics.insetRadius, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
}

private struct MenuDetailActionRow: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                Text(label)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.ink)

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, MenuDetailMetrics.horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: MenuDetailMetrics.actionMinHeight,
                   alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: MenuDetailMetrics.insetRadius, style: .continuous)
                    .fill(Theme.chipFill)
                )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .accessibilityLabel(Text(label))
        .help(label)
    }
}

private func menuSpokenValue(_ value: String) -> String {
    value == "—" ? "No data" : value
}

// MARK: - CPU

struct CPUDetailPane: View {
    let status: SystemStatus?
    let back: () -> Void

    var body: some View {
        let cpu = status?.cpu

        MenuDetailSurface {
            VStack(alignment: .leading, spacing: 0) {
                MenuDetailHeader(title: "CPU", back: back)

                if let cpu {
                    let usageStatus = Severity.level(forUsage: cpu.usage)
                    MenuDetailLine(label: "Usage", value: Fmt.percent(cpu.usage, decimals: 1),
                                   status: usageStatus)
                    MenuDetailBar(percent: cpu.usage, label: "CPU usage", status: usageStatus,
                                  valueText: Fmt.percent(cpu.usage, decimals: 1))
                        .padding(.horizontal, MenuDetailMetrics.horizontalPadding)
                        .padding(.vertical, 5)

                    if let chip = status?.hardware?.chip {
                        MenuDetailLine(label: "Chip", value: chip)
                    }
                    MenuDetailLine(label: "Cores", value: coreSummary(cpu))

                    if let perCore = cpu.perCore, !perCore.isEmpty {
                        MenuDetailSectionTitle(title: "Per core")

                        VStack(spacing: 2) {
                            ForEach(Array(perCore.enumerated()), id: \.offset) { index, value in
                                let coreStatus = Severity.level(forUsage: value)
                                HStack(spacing: 6) {
                                    Text("\(index)")
                                        .font(Theme.instrument(9))
                                        .foregroundStyle(Theme.inkTertiary)
                                        .frame(width: 14, alignment: .trailing)

                                    MenuDetailBar(percent: value, label: "Core \(index)",
                                                  status: coreStatus,
                                                  valueText: Fmt.percent(value))
                                        .accessibilityHidden(true)

                                    if let coreStatus {
                                        MenuDetailStatusMark(status: coreStatus)
                                    }

                                    Text(Fmt.percent(value))
                                        .font(Theme.mono(9, .medium))
                                        .foregroundStyle(coreStatus?.color ?? Theme.ink)
                                        .frame(width: 38, alignment: .trailing)
                                }
                                .padding(.horizontal, MenuDetailMetrics.horizontalPadding)
                                .frame(minHeight: MenuDetailMetrics.rowMinHeight)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text("Core \(index)"))
                                .accessibilityValue(Text(
                                    "\(menuSpokenValue(Fmt.percent(value))), \(coreStatus?.accessibilityLabel ?? "No status")"
                                ))
                            }
                        }
                    }

                    MenuDetailDivider()

                    MenuDetailSectionTitle(title: "Load average")
                    MenuDetailLine(label: "1 min", value: loadText(cpu.load1, cpu),
                                   status: loadStatus(cpu.load1, cpu))
                    MenuDetailLine(label: "5 min", value: loadText(cpu.load5, cpu),
                                   status: loadStatus(cpu.load5, cpu))
                    MenuDetailLine(label: "15 min", value: loadText(cpu.load15, cpu),
                                   status: loadStatus(cpu.load15, cpu))
                } else {
                    MenuDetailEmptyState(
                        icon: "cpu",
                        title: "CPU data unavailable",
                        message: status == nil
                            ? "Waiting for the first system reading."
                            : "This Mac did not report CPU metrics.",
                        actionTitle: "Return to overview",
                        action: back
                    )
                }
            }
        }
    }

    private func coreSummary(_ cpu: SystemStatus.CPU) -> String {
        guard let total = cpu.coreCount else { return "—" }
        if let p = cpu.pCoreCount, let e = cpu.eCoreCount, p + e > 0 {
            return "\(total) · \(p)P + \(e)E"
        }
        return "\(total)"
    }

    private func loadText(_ load: Double?, _ cpu: SystemStatus.CPU) -> String {
        guard let load else { return "—" }
        guard let ratio = Fmt.loadRatio(load, cores: cpu.coreCount) else {
            return Fmt.load(load)
        }
        return "\(Fmt.load(load))  (\(Fmt.percent(ratio)))"
    }

    private func loadStatus(_ load: Double?, _ cpu: SystemStatus.CPU) -> Severity.Level? {
        Severity.level(forUsage: Fmt.loadRatio(load, cores: cpu.coreCount))
    }
}

// MARK: - GPU

struct GPUDetailPane: View {
    let status: SystemStatus?
    let back: () -> Void

    var body: some View {
        let gpu = status?.gpu

        MenuDetailSurface {
            VStack(alignment: .leading, spacing: 0) {
                MenuDetailHeader(title: "GPU", back: back)

                if let gpu {
                    let utilizationStatus = Severity.level(forUsage: gpu.utilization)
                    MenuDetailLine(label: "Utilisation", value: Fmt.percent(gpu.utilization, decimals: 1),
                                   status: utilizationStatus)
                    MenuDetailBar(percent: gpu.utilization, label: "GPU utilisation",
                                  status: utilizationStatus,
                                  valueText: Fmt.percent(gpu.utilization, decimals: 1))
                        .padding(.horizontal, MenuDetailMetrics.horizontalPadding)
                        .padding(.vertical, 5)

                    if let name = gpu.name ?? status?.hardware?.chip {
                        MenuDetailLine(label: "Chip", value: name)
                    }

                    MenuDetailDivider()
                    MenuDetailSectionTitle(title: "Breakdown")

                    let rendererStatus = Severity.level(forUsage: gpu.rendererUtilization)
                    MenuDetailLine(label: "Renderer",
                                   value: Fmt.percent(gpu.rendererUtilization, decimals: 1),
                                   status: rendererStatus)
                    MenuDetailLine(label: "Tiler",
                                   value: Fmt.percent(gpu.tilerUtilization, decimals: 1),
                                   status: Severity.level(forUsage: gpu.tilerUtilization))

                    if let inUse = gpu.inUseMemory, inUse > 0 {
                        MenuDetailDivider()
                        MenuDetailLine(label: "Memory in use", value: Fmt.bytes(inUse))
                        if let allocated = gpu.allocatedMemory, allocated > 0 {
                            MenuDetailLine(label: "Allocated", value: Fmt.bytes(allocated))
                        }
                        MenuDetailNote(
                            text: "Apple silicon shares memory between CPU and GPU. This is part of RAM, not separate VRAM.",
                            icon: "info.circle"
                        )
                    }

                    MenuDetailNote(text: "Source · IOKit's IOAccelerator registry.")
                } else {
                    MenuDetailEmptyState(
                        icon: "gauge.with.dots.needle.67percent",
                        title: "GPU telemetry unavailable",
                        message: status == nil
                            ? "Waiting for the first system reading."
                            : "This Mac did not expose GPU utilisation metrics.",
                        actionTitle: "Return to overview",
                        action: back
                    )
                }
            }
        }
    }
}

// MARK: - Memory

struct MemoryDetailPane: View {
    let status: SystemStatus?
    let back: () -> Void

    var body: some View {
        let memory = status?.memory

        MenuDetailSurface {
            VStack(alignment: .leading, spacing: 0) {
                MenuDetailHeader(title: "Memory", back: back)

                if let memory {
                    let usageStatus = Severity.level(forUsage: memory.usedPercent)
                    MenuDetailLine(label: "Used", value: Fmt.percent(memory.usedPercent, decimals: 1),
                                   status: usageStatus)
                    MenuDetailBar(percent: memory.usedPercent, label: "Memory used",
                                  status: usageStatus,
                                  valueText: Fmt.percent(memory.usedPercent, decimals: 1))
                        .padding(.horizontal, MenuDetailMetrics.horizontalPadding)
                        .padding(.vertical, 5)

                    MenuDetailLine(label: "In use", value: Fmt.bytes(memory.used))
                    MenuDetailLine(label: "Available", value: Fmt.bytes(memory.available))
                    MenuDetailLine(label: "Cached", value: Fmt.bytes(memory.cached))
                    MenuDetailLine(label: "Total", value: Fmt.bytes(memory.total))

                    if let swapTotal = memory.swapTotal, swapTotal > 0 {
                        MenuDetailDivider()
                        let swapPercent = memory.swapUsed.map {
                            Double($0) / Double(swapTotal) * 100
                        }
                        let swapStatus = Severity.level(forUsage: swapPercent)
                        MenuDetailLine(label: "Swap used", value: Fmt.bytes(memory.swapUsed),
                                       status: swapStatus)
                        MenuDetailLine(label: "Swap total", value: Fmt.bytes(swapTotal))
                        if let swapPercent {
                            MenuDetailBar(percent: swapPercent, label: "Swap used",
                                          status: swapStatus,
                                          valueText: Fmt.percent(swapPercent))
                                .padding(.horizontal, MenuDetailMetrics.horizontalPadding)
                                .padding(.vertical, 5)
                        }

                        if let swapPercent, swapPercent >= 50 {
                            MenuDetailNote(
                                text: "Swap is heavy. Quitting a memory-hungry app can reduce pressure.",
                                icon: "exclamationmark.triangle.fill"
                            )
                        }
                    }
                } else {
                    MenuDetailEmptyState(
                        icon: "memorychip",
                        title: "Memory data unavailable",
                        message: status == nil
                            ? "Waiting for the first system reading."
                            : "This Mac did not report memory metrics.",
                        actionTitle: "Return to overview",
                        action: back
                    )
                }
            }
        }
    }
}

// MARK: - Storage

struct StorageDetailPane: View {
    let status: SystemStatus?
    let back: () -> Void
    let openDashboard: () -> Void

    var body: some View {
        let disks = status?.userDisks ?? []

        MenuDetailSurface {
            VStack(alignment: .leading, spacing: 0) {
                MenuDetailHeader(title: "Storage", back: back)

                if disks.isEmpty {
                    MenuDetailEmptyState(
                        icon: "externaldrive",
                        title: "No storage volumes",
                        message: status == nil
                            ? "Waiting for the first system reading."
                            : "Vitality did not receive a user disk to show.",
                        actionTitle: "Manage storage…",
                        action: openDashboard
                    )
                } else {
                    ForEach(disks) { disk in
                        storageRow(disk)
                    }
                }

                MenuDetailDivider()
                MenuDetailActionRow(icon: "folder.badge.gearshape",
                                    label: "Manage storage…", action: openDashboard)
            }
        }
    }

    private func storageRow(_ disk: SystemStatus.Disk) -> some View {
        let diskStatus = Severity.level(forUsage: disk.usedPercent)
        let percentText = Fmt.percent(disk.usedPercent)
        let freeText = Fmt.bytes(disk.free)
        let usedText = Fmt.bytes(disk.used) + " of " + Fmt.bytes(disk.total)
        let externalText = disk.isInternal == false ? ", external disk" : ""

        return MenuDetailInset {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(disk.displayName)
                        .font(Theme.body(11, .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if disk.isInternal == false {
                        Image(systemName: "externaldrive")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.inkTertiary)
                            .accessibilityHidden(true)
                    }

                    Spacer(minLength: 5)
                    if let diskStatus {
                        MenuDetailStatusMark(status: diskStatus)
                    }
                    Text(percentText)
                        .font(Theme.mono(11, .medium))
                        .foregroundStyle(diskStatus?.color ?? Theme.ink)
                }

                MenuDetailBar(percent: disk.usedPercent, label: disk.displayName + " usage",
                              status: diskStatus, valueText: percentText)
                    .accessibilityHidden(true)

                HStack(spacing: 4) {
                    Text(freeText)
                        .font(Theme.mono(10, .medium))
                        .foregroundStyle(Theme.inkSecondary)
                    Text("FREE")
                        .font(Theme.instrument(9))
                        .tracking(0.8)
                        .foregroundStyle(Theme.inkTertiary)
                    Spacer(minLength: 8)
                    Text(usedText)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.inkTertiary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(disk.displayName))
            .accessibilityValue(Text(
                menuSpokenValue(percentText) + externalText + ", "
                    + menuSpokenValue(freeText) + " free, "
                    + menuSpokenValue(usedText) + ", "
                    + (diskStatus?.accessibilityLabel ?? "No status")
            ))
        }
    }
}

// MARK: - Temperature

struct ThermalDetailPane: View {
    let status: SystemStatus?
    let back: () -> Void
    let openDashboard: () -> Void

    var body: some View {
        let thermal = status?.thermal

        MenuDetailSurface {
            VStack(alignment: .leading, spacing: 0) {
                MenuDetailHeader(title: "Temperature", back: back)

                if let thermal, !thermal.sensors.isEmpty {
                    thermalLine(label: "CPU", value: thermal.cpu)
                    TemperatureBar(celsius: thermal.cpu)

                    thermalLine(label: "Performance cores", value: thermal.performanceCores)
                    thermalLine(label: "Efficiency cores", value: thermal.efficiencyCores)

                    MenuDetailDivider()

                    thermalLine(label: "GPU", value: thermal.gpu)
                    TemperatureBar(celsius: thermal.gpu)

                    MenuDetailDivider()

                    if thermal.battery != nil {
                        thermalLine(label: "Battery", value: thermal.battery)
                    }
                    thermalLine(label: "Storage", value: thermal.storage)
                    thermalLine(label: "Enclosure", value: thermal.enclosure)

                    if let hottest = thermal.hottest {
                        MenuDetailDivider()
                        thermalLine(label: "Hottest sensor", value: hottest.celsius)
                        MenuDetailNote(
                            text: (hottest.isIdentified ? hottest.label : "Unidentified sensor") + " · " + hottest.key,
                            icon: hottest.isIdentified ? "thermometer.medium" : "questionmark.circle"
                        )
                    }

                    MenuDetailNote(
                        text: "Cluster figures are the mean of each sensor in that cluster. Apple silicon idles near 50° and throttles above 100°, so warm is normal.",
                        icon: "info.circle"
                    )

                    MenuDetailDivider()
                    MenuDetailActionRow(icon: "list.bullet.rectangle",
                                        label: "All " + String(thermal.sensors.count) + " sensors…",
                                        action: openDashboard)
                } else {
                    MenuDetailEmptyState(
                        icon: "thermometer.medium",
                        title: "No temperature sensors",
                        message: status == nil
                            ? "Waiting for the first system reading."
                            : "This Mac did not report temperature sensors.",
                        actionTitle: "Open sensor details",
                        action: openDashboard
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func thermalLine(label: String, value: Double?) -> some View {
        let thermalStatus = Severity.level(forTemperature: value)
        MenuDetailLine(label: label, value: Fmt.celsius(value, decimals: 1),
                       status: thermalStatus)
    }
}

/// A usage bar scaled to a die's real range rather than 0–100%.
///
/// Reusing `MiniBar` would put a 50° idle chip at the halfway mark and imply
/// it is working hard. Anchoring at 30° makes the bar track what actually
/// changes.
struct TemperatureBar: View {
    let celsius: Double?

    var body: some View {
        MenuDetailBar(
            percent: celsius.map { max(0, min(100, ($0 - 30) / 70 * 100)) },
            label: "Temperature",
            status: Severity.level(forTemperature: celsius),
            valueText: Fmt.celsius(celsius, decimals: 1)
        )
        .padding(.horizontal, MenuDetailMetrics.horizontalPadding)
        .padding(.vertical, 5)
    }
}

// MARK: - Power & battery

struct PowerDetailPane: View {
    let status: SystemStatus?
    let back: () -> Void

    var body: some View {
        let power = status?.power
        let battery = status?.battery

        MenuDetailSurface {
            VStack(alignment: .leading, spacing: 0) {
                MenuDetailHeader(title: "Power", back: back)

                if power == nil && battery == nil {
                    MenuDetailEmptyState(
                        icon: "bolt.batteryblock",
                        title: "Power data unavailable",
                        message: status == nil
                            ? "Waiting for the first system reading."
                            : "This Mac did not report power or battery metrics.",
                        actionTitle: "Return to overview",
                        action: back
                    )
                } else {
                    if let used = power?.systemWatts {
                        MenuDetailLine(label: "Drawing now", value: Fmt.watts(used))
                    }
                    if let input = power?.inputWatts {
                        MenuDetailLine(label: "Coming in", value: Fmt.watts(input))
                    }

                    if let used = power?.systemWatts, let input = power?.inputWatts, input > used {
                        MenuDetailLine(label: "To battery & losses", value: Fmt.watts(input - used))
                    }

                    if power?.systemWatts != nil { MenuDetailDivider() }

                    if let adapter = power?.adapterWatts, adapter > 0 {
                        MenuDetailLine(label: "Adapter rating", value: Fmt.watts(adapter))
                    }
                    if let draw = power?.batteryWatts, draw > 0 {
                        MenuDetailLine(label: power?.isCharging == true ? "Charging at" : "Battery draw",
                                       value: Fmt.watts(draw))
                    }
                    if let isOnAC = power?.isOnAC {
                        MenuDetailLine(label: "Source", value: isOnAC ? "Wall power" : "Battery")
                    }

                    if let battery {
                        MenuDetailDivider()
                        MenuDetailSectionTitle(title: "Battery")

                        let chargeStatus = Severity.level(forCharge: battery.percent.map(Double.init))
                        MenuDetailLine(label: "Charge",
                                       value: battery.percent.map { Fmt.percent(Double($0)) } ?? "—",
                                       status: chargeStatus)
                        MenuDetailBar(
                            percent: battery.percent.map(Double.init),
                            label: "Battery charge",
                            status: chargeStatus,
                            valueText: battery.percent.map { Fmt.percent(Double($0)) }
                        )
                        .padding(.horizontal, MenuDetailMetrics.horizontalPadding)
                        .padding(.vertical, 5)

                        MenuDetailLine(label: "Status", value: battery.status ?? "—")
                        if let timeLeft = battery.timeLeft, !timeLeft.isEmpty {
                            MenuDetailLine(label: "Time left", value: timeLeft)
                        }
                        if let health = battery.health {
                            MenuDetailLine(label: "Health", value: health)
                        }
                        if let capacity = battery.capacity, capacity > 0 {
                            MenuDetailLine(label: "Max capacity", value: String(capacity) + "%",
                                           tint: capacity < 80 ? Theme.statusWarn : Theme.ink,
                                           status: batteryCapacityStatus(capacity))
                        }
                        if let cycles = battery.cycleCount, cycles > 0 {
                            MenuDetailLine(label: "Cycles", value: String(cycles))
                        }
                    }
                }
            }
        }
    }

    private func batteryCapacityStatus(_ capacity: Int) -> Severity.Level? {
        if capacity < 50 { return .critical }
        if capacity < 80 { return .warning }
        return .normal
    }
}

// MARK: - Processes

struct ProcessesDetailPane: View {
    let status: SystemStatus?
    let back: () -> Void
    let openDashboard: () -> Void

    var body: some View {
        let processes = status?.processes ?? []

        MenuDetailSurface {
            VStack(alignment: .leading, spacing: 0) {
                MenuDetailHeader(title: "Top processes", back: back)

                if processes.isEmpty {
                    MenuDetailEmptyState(
                        icon: "list.bullet.rectangle",
                        title: "No process data",
                        message: status == nil
                            ? "Waiting for the first system reading."
                            : "Vitality did not receive a process sample.",
                        actionTitle: "Manage processes…",
                        action: openDashboard
                    )
                } else {
                    ForEach(processes) { process in
                        processRow(process)
                    }
                }

                MenuDetailDivider()
                MenuDetailActionRow(icon: "xmark.circle",
                                    label: "Manage processes…", action: openDashboard)
            }
        }
    }

    private func processRow(_ process: SystemStatus.TopProcess) -> some View {
        let processName = process.name ?? "Unknown process"
        let cpuText = Fmt.percent(process.cpu, decimals: 1)
        let processStatus = Severity.level(forUsage: process.cpu)
        let pidText = process.pid.map(String.init) ?? "—"
        let memoryText = Fmt.bytes(process.memoryBytes)

        return MenuDetailInset {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(processName)
                        .font(Theme.body(11, .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)

                    Spacer(minLength: 5)
                    if let processStatus {
                        MenuDetailStatusMark(status: processStatus)
                    }
                    Text(cpuText)
                        .font(Theme.mono(11, .medium))
                        .foregroundStyle(processStatus?.color ?? Theme.ink)
                }

                HStack(spacing: 6) {
                    Text("PID \(pidText)")
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.inkTertiary)
                    Spacer(minLength: 8)
                    Text(memoryText)
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(processName))
            .accessibilityValue(Text(
                "CPU \(menuSpokenValue(cpuText)), process ID \(menuSpokenValue(pidText)), memory \(menuSpokenValue(memoryText)), \(processStatus?.accessibilityLabel ?? "No status")"
            ))
        }
    }
}
