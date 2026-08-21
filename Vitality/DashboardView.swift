import SwiftUI

/// The dashboard's sections. A sidebar rather than a TabView: four tabs was
/// already crowded, and Network, Battery and Alerts would have made it seven.
enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case activity = "Activity"
    case network = "Network"
    case storage = "Storage"
    case battery = "Battery"
    case sensors = "Sensors"
    case alerts = "Alerts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "gauge.medium"
        case .activity: return "list.bullet.rectangle"
        case .network:  return "arrow.up.arrow.down"
        case .storage:  return "internaldrive"
        case .battery:  return "battery.75percent"
        case .sensors:  return "thermometer.medium"
        case .alerts:   return "bell.badge"
        }
    }
}

struct DashboardView: View {
    @ObservedObject var poller: StatusPoller
    let history: MetricsHistoryStore
    @ObservedObject var alerts: AlertCenter
    @State private var section: DashboardSection = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section {
                    ForEach([DashboardSection.overview, .activity, .network,
                             .storage, .battery, .sensors]) { section in
                        Label(section.rawValue, systemImage: section.icon).tag(section)
                    }
                }
                Section("Settings") {
                    Label {
                        Text(DashboardSection.alerts.rawValue)
                    } icon: {
                        Image(systemName: DashboardSection.alerts.icon)
                    }
                    .badge(alerts.active.count)
                    .tag(DashboardSection.alerts)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 185, max: 220)
        } detail: {
            Group {
                switch section {
                case .overview:
                    OverviewPane(poller: poller, history: history, alerts: alerts,
                                 openSection: { section = $0 })
                case .activity: ProcessesView()
                case .network:  NetworkPane(poller: poller, history: history)
                case .storage:  StorageView(poller: poller)
                case .battery:  BatteryPane(poller: poller, history: history)
                case .sensors:  SensorsView(poller: poller)
                case .alerts:   AlertsPane(alerts: alerts)
                }
            }
            .padding(14)
            .frame(minWidth: 560)
        }
        .frame(minWidth: 780, minHeight: 520)
    }
}

// MARK: - Overview

struct OverviewPane: View {
    @ObservedObject var poller: StatusPoller
    @ObservedObject var history: MetricsHistoryStore
    @ObservedObject var alerts: AlertCenter
    let openSection: (DashboardSection) -> Void

    @State private var range: HistoryRange = .day

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let status = poller.latest {
                    HStack {
                        Text("Overview").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        RangePicker(range: $range)
                    }
                    statusHeader(status)
                    alertList
                    metrics(status)
                    activity(status)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func statusHeader(_ status: SystemStatus) -> some View {
        HStack(spacing: 16) {
            ZStack {
                HealthRing(score: status.healthScore, lineWidth: 7)
                VStack(spacing: 0) {
                    Text(status.healthScore.map(String.init) ?? "—")
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    Text("health")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 66, height: 66)

            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle(status))
                    .font(.system(size: 16, weight: .semibold))
                Text(status.healthScoreMsg ?? "Limited data")
                    .font(.system(size: 11))
                    .foregroundStyle(Severity.forHealth(status.healthScore))
                Text([status.hardware?.model ?? status.host,
                      status.hardware?.chip,
                      status.hardware?.totalRAM.map { Fmt.bytes($0) },
                      status.hardware?.osVersion]
                        .compactMap { $0 }.joined(separator: " · ")
                     + " · up \(status.uptime ?? "—")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            // The three questions a glance actually asks: how busy, how thirsty,
            // how full.
            HStack(spacing: 8) {
                quickChip(Fmt.percent(status.cpu?.usage), "CPU now")
                quickChip(Fmt.watts(status.headlinePower), "power")
                quickChip(Fmt.bytes(status.primaryDisk?.free), "disk free")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(status.healthScore == nil
                  ? Color.primary.opacity(0.04)
                  : Severity.forHealth(status.healthScore).opacity(0.08)))
    }

    private func quickChip(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value).font(.system(size: 14, weight: .semibold).monospacedDigit())
            Text(label).font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func statusTitle(_ status: SystemStatus) -> String {
        guard let score = status.healthScore else { return "Limited data" }
        switch score {
        case 90...: return "Your Mac is healthy"
        case 75..<90: return "Your Mac is doing well"
        case 55..<75: return "Your Mac needs attention"
        default: return "Your Mac is under pressure"
        }
    }

    @ViewBuilder
    private var alertList: some View {
        if alerts.active.isEmpty {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("No action needed — everything is within normal range.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.green.opacity(0.06)))
        } else {
            VStack(spacing: 7) {
                ForEach(alerts.active) { alert in
                    AlertCard(alert: alert) {
                        switch alert.action {
                        case .openStorage:  openSection(.storage)
                        case .openActivity: openSection(.activity)
                        case .openSensors:  openSection(.sensors)
                        case .none:         break
                        }
                    } snooze: {
                        alerts.snooze(alert.id)
                    }
                }
            }
        }
    }

    private func metrics(_ status: SystemStatus) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12, alignment: .top),
            GridItem(.flexible(), spacing: 12, alignment: .top),
        ], spacing: 12) {
            HistoryChartCard(
                label: "CPU",
                currentText: Fmt.percent(status.cpu?.usage, decimals: 1),
                subtitle: "\(status.cpu?.coreCount.map(String.init) ?? "—") cores · load \(Fmt.load(status.cpu?.load1))",
                points: history.series(.cpu, range: range),
                scale: .percent, tint: .blue,
                stats: history.stats(.cpu, range: range)
            ) { openSection(.activity) }

            HistoryChartCard(
                label: "GPU",
                currentText: Fmt.percent(status.gpu?.utilization, decimals: 1),
                subtitle: status.gpu?.inUseMemory.map { Fmt.bytes($0) + " in use" } ?? "No GPU data",
                points: history.series(.gpu, range: range),
                scale: .percent, tint: .orange,
                stats: history.stats(.gpu, range: range)
            ) { openSection(.sensors) }

            HistoryChartCard(
                label: "Memory",
                currentText: Fmt.percent(status.memory?.usedPercent, decimals: 1),
                subtitle: Fmt.bytes(status.memory?.used) + " of " + Fmt.bytes(status.memory?.total),
                points: history.series(.memory, range: range),
                scale: .percent, tint: .teal,
                stats: history.stats(.memory, range: range)
            ) { openSection(.activity) }

            HistoryChartCard(
                label: "Disk",
                currentText: Fmt.percent(status.primaryDisk?.usedPercent),
                subtitle: Fmt.bytes(status.primaryDisk?.free) + " free",
                points: history.series(.disk, range: range),
                scale: .percent, tint: .yellow,
                stats: history.stats(.disk, range: range)
            ) { openSection(.storage) }
        }
    }

    private func activity(_ status: SystemStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Top activity")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Activity") { openSection(.activity) }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }

            ForEach(status.processes.prefix(3)) { process in
                HStack {
                    Text(process.name ?? "—")
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                    Text(Fmt.bytes(process.memoryBytes))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(Fmt.percent(process.cpu, decimals: 1))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Severity.forUsage(process.cpu))
                        .frame(width: 58, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }

            if status.processes.isEmpty {
                Text("No process data yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(Color.primary.opacity(0.04)))
    }
}

/// One firing alert, with its action and a snooze affordance.
struct AlertCard: View {
    let alert: ActiveAlert
    let action: () -> Void
    let snooze: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: alert.severity == .critical
                  ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(alert.severity.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(alert.title).font(.system(size: 12, weight: .semibold))
                Text(alert.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let label = alert.actionLabel {
                Button(label, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Button("Snooze", action: snooze)
                .buttonStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .help("Hide this alert and its notifications for 6 hours")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(alert.severity.color.opacity(0.08)))
    }
}
