import SwiftUI

// MARK: - Activity

enum ActivityMode: String, CaseIterable, Identifiable {
    case processes = "Processes"
    case network = "Network"

    var id: String { rawValue }
}

struct ActivityPane: View {
    @ObservedObject var poller: StatusPoller
    @ObservedObject var history: MetricsHistoryStore
    let initialProcessSort: ProcessSort
    @Binding var mode: ActivityMode

    init(poller: StatusPoller, history: MetricsHistoryStore,
         initialProcessSort: ProcessSort = .cpu,
         mode: Binding<ActivityMode> = .constant(.processes)) {
        _poller = ObservedObject(wrappedValue: poller)
        _history = ObservedObject(wrappedValue: history)
        self.initialProcessSort = initialProcessSort
        _mode = mode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionGap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACTIVITY")
                        .font(Theme.mono(20, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("PROCESSES AND NETWORK")
                        .font(Theme.mono(10, .medium))
                        .tracking(2)
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                Picker("Activity view", selection: $mode) {
                    ForEach(ActivityMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            switch mode {
            case .processes:
                ProcessesView(initialSort: initialProcessSort)
            case .network:
                NetworkPane(poller: poller, history: history)
            }
        }
    }
}

// MARK: - Network

/// Download and upload are separate charts on purpose. Down traffic usually
/// dwarfs up by an order of magnitude, so sharing one axis flattens the upload
/// into a floor line; and two y-scales on one plot is the classic chart lie.
struct NetworkPane: View {
    @ObservedObject var poller: StatusPoller
    @ObservedObject var history: MetricsHistoryStore

    @State private var range: HistoryRange = .hour

    var body: some View {
        let network = poller.latest?.network

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Network")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if let interface = network?.interface {
                        Text(interface)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    Spacer()
                    RangePicker(range: $range)
                }

                HStack(spacing: 12) {
                    headline("arrow.down.circle.fill", Fmt.rate(network?.downBytesPerSec),
                             "download", Theme.slotCPU)
                    headline("arrow.up.circle.fill", Fmt.rate(network?.upBytesPerSec),
                             "upload", Theme.slotGPU)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("this session")
                            .font(.system(size: 9)).foregroundStyle(Theme.inkTertiary)
                        Text("↓ \(Fmt.bytes(network?.sessionDownBytes))  ·  ↑ \(Fmt.bytes(network?.sessionUpBytes))")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }

                HistoryChartCard(
                    label: "Download",
                    currentText: Fmt.rate(network?.downBytesPerSec),
                    points: history.series(.netDown, range: range),
                    scale: .relative, tint: Theme.slotCPU,
                    accessibilityRange: range.label,
                    stats: history.stats(.netDown, range: range),
                    format: { Fmt.rate($0) },
                    showsCalendarDate: range.showsCalendarDate
                )

                HistoryChartCard(
                    label: "Upload",
                    currentText: Fmt.rate(network?.upBytesPerSec),
                    points: history.series(.netUp, range: range),
                    scale: .relative, tint: Theme.slotGPU,
                    accessibilityRange: range.label,
                    stats: history.stats(.netUp, range: range),
                    format: { Fmt.rate($0) },
                    showsCalendarDate: range.showsCalendarDate
                )

                Text("Measured across the Mac's physical interfaces. Session totals reset when Vitality quits.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.vertical, 4)
        }
    }

    private func headline(_ icon: String, _ value: String, _ label: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                Text(label).font(.system(size: 9)).foregroundStyle(Theme.inkTertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(ThemeCardBackground(radius: Theme.nestedRadius))
    }
}

// MARK: - Power

struct PowerPane: View {
    @ObservedObject var poller: StatusPoller
    @ObservedObject var history: MetricsHistoryStore

    var body: some View {
        let status = poller.latest
        let battery = status?.battery
        let power = status?.power

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("POWER")
                    .font(Theme.mono(20, .semibold))
                    .foregroundStyle(Theme.ink)

                powerCard(status: status)

                if let battery {
                    chargeCard(battery, power: power)
                    healthCard(battery)
                    healthTrend
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "powerplug.fill")
                            .font(.system(size: 18)).foregroundStyle(Theme.inkSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No battery")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Text("This Mac runs on wall power. Power monitoring remains available above.")
                                .font(.system(size: 11)).foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer()
                    }
                    .padding(13)
                    .background(ThemeCardBackground())
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func powerCard(status: SystemStatus?) -> some View {
        let power = status?.power
        return VStack(alignment: .leading, spacing: 12) {
            ThemeCardHeader(number: "01", title: "LIVE DRAW",
                            trailing: power.flatMap { $0.isOnAC.map { $0 ? "AC" : "BATTERY" } })
            HStack(spacing: 24) {
                detail(status?.headlinePowerLabel ?? "Power draw", Fmt.watts(status?.headlinePower),
                       tint: Theme.accent)
                detail("Coming in", Fmt.watts(power?.inputWatts))
                detail("Adapter rating", Fmt.watts(power?.adapterWatts))
                if let batteryWatts = power?.batteryWatts {
                    detail(power?.isCharging == true ? "Battery charge" : "Battery draw",
                           Fmt.watts(batteryWatts))
                }
                Spacer()
            }
        }
        .padding(13)
        .background(ThemeCardBackground())
        .accessibilityElement(children: .contain)
    }

    private func chargeCard(_ battery: SystemStatus.Battery, power: SystemStatus.Power?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Charge").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                Spacer()
                Text(battery.percent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
            }
            MiniBar(percent: battery.percent.map(Double.init), height: 6,
                    tint: Severity.forCharge(battery.percent.map(Double.init)),
                    accessibilityLabel: "Charge")

            HStack(spacing: 16) {
                detail("Status", battery.status ?? "—")
                if let timeLeft = battery.timeLeft, !timeLeft.isEmpty {
                    detail("Time left", timeLeft)
                }
                if let watts = power?.batteryWatts, watts > 0 {
                    detail(power?.isCharging == true ? "Charging at" : "Draw", Fmt.watts(watts))
                }
                Spacer()
            }
        }
        .padding(13)
        .background(ThemeCardBackground())
    }

    private func healthCard(_ battery: SystemStatus.Battery) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Health").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
            HStack(spacing: 16) {
                if let capacity = battery.capacity, capacity > 0 {
                    // Apple considers a battery for service below 80%.
                    detail("Max capacity", "\(capacity)%",
                           tint: capacity < 80 ? Theme.statusWarn : Theme.ink)
                }
                if let cycles = battery.cycleCount, cycles > 0 {
                    detail("Cycles", "\(cycles)")
                }
                if let condition = battery.health {
                    detail("Condition", condition)
                }
                Spacer()
            }
        }
        .padding(13)
        .background(ThemeCardBackground())
    }

    @ViewBuilder
    private var healthTrend: some View {
        let days = history.batteryHealthDays
        VStack(alignment: .leading, spacing: 8) {
            Text("Max capacity over time")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkSecondary)

            if days.count > 1 {
                HistoryChart(
                    points: days.map { HistoryPoint(date: $0.day, value: Double($0.capacityPercent)) },
                    scale: .percent, tint: Theme.statusGood, height: 80,
                    format: { Fmt.percent($0) },
                    showsCalendarDate: true
                )
                .equatable()
                HStack {
                    Text(days.first!.day, format: .dateTime.day().month())
                    Spacer()
                    if let first = days.first, let last = days.last,
                       first.capacityPercent != last.capacityPercent {
                        Text("\(last.capacityPercent - first.capacityPercent)% since \(first.day, format: .dateTime.month().year())")
                    }
                }
                .font(.system(size: 10)).foregroundStyle(Theme.inkTertiary)
            } else {
                // Health moves over months. One sample per day is the honest
                // cadence, which means the chart earns its place slowly.
                Text("Vitality records one health sample per day. The trend appears after a couple of days of use.")
                    .font(.system(size: 10)).foregroundStyle(Theme.inkTertiary)
            }
        }
        .padding(13)
        .background(ThemeCardBackground())
    }

    private func detail(_ label: String, _ value: String, tint: Color = Theme.ink) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(tint)
            Text(label).font(.system(size: 9)).foregroundStyle(Theme.inkTertiary)
        }
    }
}

// MARK: - Alerts settings

struct AlertsPane: View {
    @ObservedObject var alerts: AlertCenter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Alerts")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                Toggle(isOn: $alerts.notificationsEnabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Notifications")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Text("Vitality notifies at most once per rule every 6 hours.")
                            .font(.system(size: 10)).foregroundStyle(Theme.inkTertiary)
                    }
                }
                .toggleStyle(.switch)
                .padding(13)
                .background(ThemeCardBackground())

                VStack(spacing: 0) {
                    ForEach(AlertCenter.allRules) { rule in
                        HStack(spacing: 11) {
                            Image(systemName: rule.icon)
                                .foregroundStyle(Theme.inkSecondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Text(rule.detail).font(.system(size: 10)).foregroundStyle(Theme.inkTertiary)
                            }
                            Spacer()
                            Toggle("", isOn: alerts.binding(for: rule.id))
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 13).padding(.vertical, 9)
                        if rule.id != AlertCenter.allRules.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(ThemeCardBackground())

                Text("Alerts appear on the Overview as they fire. Sustained conditions (CPU, swap, temperature) must hold for a while before firing, so a momentary spike never nags you.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }
}
