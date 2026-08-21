import SwiftUI

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
                    Text("Network").font(.system(size: 15, weight: .semibold))
                    if let interface = network?.interface {
                        Text(interface)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    RangePicker(range: $range)
                }

                HStack(spacing: 12) {
                    headline("arrow.down.circle.fill", Fmt.rate(network?.downBytesPerSec),
                             "download", .blue)
                    headline("arrow.up.circle.fill", Fmt.rate(network?.upBytesPerSec),
                             "upload", .orange)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("this session")
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                        Text("↓ \(Fmt.bytes(network?.sessionDownBytes))  ·  ↑ \(Fmt.bytes(network?.sessionUpBytes))")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                HistoryChartCard(
                    label: "Download",
                    currentText: Fmt.rate(network?.downBytesPerSec),
                    points: history.series(.netDown, range: range),
                    scale: .relative, tint: .blue,
                    stats: history.stats(.netDown, range: range),
                    format: { Fmt.rate($0) }
                )

                HistoryChartCard(
                    label: "Upload",
                    currentText: Fmt.rate(network?.upBytesPerSec),
                    points: history.series(.netUp, range: range),
                    scale: .relative, tint: .orange,
                    stats: history.stats(.netUp, range: range),
                    format: { Fmt.rate($0) }
                )

                Text("Measured across the Mac's physical interfaces. Session totals reset when Vitality quits.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
    }

    private func headline(_ icon: String, _ value: String, _ label: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 17, weight: .semibold).monospacedDigit())
                Text(label).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Battery

struct BatteryPane: View {
    @ObservedObject var poller: StatusPoller
    @ObservedObject var history: MetricsHistoryStore

    var body: some View {
        let status = poller.latest
        let battery = status?.battery
        let power = status?.power

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Battery").font(.system(size: 15, weight: .semibold))

                if let battery {
                    chargeCard(battery, power: power)
                    healthCard(battery)
                    healthTrend
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "powerplug.fill")
                            .font(.system(size: 28)).foregroundStyle(.tertiary)
                        Text("No battery").font(.system(size: 13, weight: .medium))
                        Text("This Mac runs on wall power only.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chargeCard(_ battery: SystemStatus.Battery, power: SystemStatus.Power?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Charge").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(battery.percent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
            }
            MiniBar(percent: battery.percent.map(Double.init), height: 6)

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
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }

    private func healthCard(_ battery: SystemStatus.Battery) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Health").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                if let capacity = battery.capacity, capacity > 0 {
                    // Apple considers a battery for service below 80%.
                    detail("Max capacity", "\(capacity)%",
                           tint: capacity < 80 ? .orange : .primary)
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
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }

    @ViewBuilder
    private var healthTrend: some View {
        let days = history.batteryHealthDays
        VStack(alignment: .leading, spacing: 8) {
            Text("Max capacity over time")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)

            if days.count > 1 {
                HistoryChart(
                    points: days.map { HistoryPoint(date: $0.day, value: Double($0.capacityPercent)) },
                    scale: .percent, tint: .green, height: 80,
                    format: { Fmt.percent($0) }
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
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            } else {
                // Health moves over months. One sample per day is the honest
                // cadence, which means the chart earns its place slowly.
                Text("Vitality records one health sample per day. The trend appears after a couple of days of use.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }

    private func detail(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(tint)
            Text(label).font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Alerts settings

struct AlertsPane: View {
    @ObservedObject var alerts: AlertCenter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Alerts").font(.system(size: 15, weight: .semibold))

                Toggle(isOn: $alerts.notificationsEnabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Notifications").font(.system(size: 12, weight: .medium))
                        Text("Vitality notifies at most once per rule every 6 hours.")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.switch)
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))

                VStack(spacing: 0) {
                    ForEach(AlertCenter.allRules) { rule in
                        HStack(spacing: 11) {
                            Image(systemName: rule.icon)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.title).font(.system(size: 12, weight: .medium))
                                Text(rule.detail).font(.system(size: 10)).foregroundStyle(.tertiary)
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
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))

                Text("Alerts appear on the Overview as they fire. Sustained conditions (CPU, swap, temperature) must hold for a while before firing, so a momentary spike never nags you.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }
}
