import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case processes = "Activity"
    case storage = "Storage"
    case sensors = "Hardware"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview:  return "gauge.medium"
        case .processes: return "list.bullet.rectangle"
        case .storage:   return "internaldrive"
        case .sensors:   return "thermometer.medium"
        }
    }
}

struct DashboardView: View {
    @ObservedObject var poller: StatusPoller
    @State private var tab: DashboardTab = .overview

    var body: some View {
        TabView(selection: $tab) {
            OverviewView(poller: poller) { tab = $0 }
                .tabItem { Label(DashboardTab.overview.rawValue,
                                 systemImage: DashboardTab.overview.icon) }
                .tag(DashboardTab.overview)

            ProcessesView()
                .tabItem { Label(DashboardTab.processes.rawValue,
                                 systemImage: DashboardTab.processes.icon) }
                .tag(DashboardTab.processes)

            StorageView(poller: poller)
                .tabItem { Label(DashboardTab.storage.rawValue,
                                 systemImage: DashboardTab.storage.icon) }
                .tag(DashboardTab.storage)

            SensorsView(poller: poller)
                .tabItem { Label(DashboardTab.sensors.rawValue,
                                 systemImage: DashboardTab.sensors.icon) }
                .tag(DashboardTab.sensors)
        }
        .padding(14)
        .frame(minWidth: 620, minHeight: 460)
    }
}

// MARK: - Overview

struct OverviewView: View {
    @ObservedObject var poller: StatusPoller
    let openTab: (DashboardTab) -> Void
    @StateObject private var history: DashboardHistory

    init(poller: StatusPoller, openTab: @escaping (DashboardTab) -> Void = { _ in }) {
        self.poller = poller
        self.openTab = openTab
        _history = StateObject(wrappedValue: DashboardHistory(poller: poller))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let status = poller.latest {
                    statusHeader(status)
                    insights(status)
                    metrics(status)
                    activity(status)
                } else if let error = poller.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding()
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func statusHeader(_ status: SystemStatus) -> some View {
        HStack(spacing: 14) {
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
                Text(status.hardware?.model ?? status.host ?? "This Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text([status.hardware?.chip,
                      status.hardware?.totalRAM.map { Fmt.bytes($0) },
                      status.hardware?.osVersion]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Updated " + Fmt.relativeTime(from: status.collectedAt) + " · " + (status.healthScoreMsg ?? "Limited data"))
                    .font(.system(size: 10))
                    .foregroundStyle(Severity.forHealth(status.healthScore))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(status.healthScore == nil
                  ? Color.primary.opacity(0.04)
                  : Severity.forHealth(status.healthScore).opacity(0.08)))
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

    private func insights(_ status: SystemStatus) -> some View {
        let items = OverviewInsights.evaluate(status: status, history: history)
        return VStack(alignment: .leading, spacing: 7) {
            Text("What needs attention?")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(items) { insight in
                OverviewInsightRow(insight: insight) {
                    if let tab = insight.actionTab { openTab(tab) }
                }
            }
        }
    }

    private func metrics(_ status: SystemStatus) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12, alignment: .leading),
            GridItem(.flexible(), spacing: 12, alignment: .leading),
        ], spacing: 12) {
            OverviewMetricCard(
                label: "CPU", value: Fmt.percent(status.cpu?.usage, decimals: 1),
                detail: "Load " + Fmt.load(status.cpu?.load1) + " · " + (status.cpu?.coreCount.map(String.init) ?? "—") + " cores",
                values: history.values(\.cpu), scale: .percent, tint: .blue
            ) { openTab(.processes) }

            OverviewMetricCard(
                label: "GPU", value: Fmt.percent(status.gpu?.utilization, decimals: 1),
                detail: status.gpu?.inUseMemory.map { Fmt.bytes($0) + " in use" } ?? "No GPU data",
                values: history.values(\.gpu), scale: .percent, tint: .purple
            ) { openTab(.sensors) }

            OverviewMetricCard(
                label: "Memory", value: Fmt.percent(status.memory?.usedPercent, decimals: 1),
                detail: Fmt.bytes(status.memory?.used) + " of " + Fmt.bytes(status.memory?.total),
                values: history.values(\.memory), scale: .percent, tint: .teal
            ) { openTab(.processes) }

            OverviewMetricCard(
                label: "Disk", value: Fmt.percent(status.primaryDisk?.usedPercent),
                detail: Fmt.bytes(status.primaryDisk?.free) + " free",
                values: history.values(\.disk), scale: .percent, tint: .orange
            ) { openTab(.storage) }
        }
    }

    private func activity(_ status: SystemStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Top activity")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Activity") { openTab(.processes) }
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
