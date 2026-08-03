import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case processes = "Processes"
    case storage = "Storage"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview:  return "gauge.medium"
        case .processes: return "list.bullet.rectangle"
        case .storage:   return "internaldrive"
        }
    }
}

struct DashboardView: View {
    @ObservedObject var poller: StatusPoller
    @State private var tab: DashboardTab = .overview

    var body: some View {
        TabView(selection: $tab) {
            OverviewView(poller: poller)
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
        }
        .padding(14)
        .frame(minWidth: 620, minHeight: 460)
    }
}

// MARK: - Overview

struct OverviewView: View {
    @ObservedObject var poller: StatusPoller

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let status = poller.latest {
                    header(status)
                    metrics(status)
                    if !status.processes.isEmpty { topProcesses(status) }
                } else if let error = poller.lastError {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding()
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func header(_ status: SystemStatus) -> some View {
        HStack(spacing: 14) {
            ZStack {
                HealthRing(score: status.healthScore, lineWidth: 7)
                VStack(spacing: 0) {
                    Text(status.healthScore.map(String.init) ?? "—")
                        .font(.system(size: 20, weight: .semibold))
                    Text("health").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 66, height: 66)

            VStack(alignment: .leading, spacing: 3) {
                Text(status.hardware?.model ?? status.host ?? "This Mac")
                    .font(.system(size: 15, weight: .semibold))
                Text([status.hardware?.cpuModel,
                      status.hardware?.totalRam,
                      status.hardware?.osVersion]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Up \(status.uptime ?? "—") · \(status.procs.map(String.init) ?? "—") processes · \(status.healthScoreMsg ?? "")")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private func metrics(_ status: SystemStatus) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            card("CPU", Fmt.percent(status.cpu?.usage, decimals: 1), status.cpu?.usage,
                 detail: "Load \(Fmt.load(status.cpu?.load1)) · \(status.cpu?.coreCount.map(String.init) ?? "—") cores")
            if let gpu = status.measuredGPU, gpu.utilization != nil {
                card("GPU", Fmt.percent(gpu.utilization, decimals: 1), gpu.utilization,
                     detail: gpu.inUseMemory.map { "\(Fmt.bytes($0)) in use" }
                         ?? (gpu.name ?? "—"))
            }
            card("Memory", Fmt.percent(status.memory?.usedPercent, decimals: 1), status.memory?.usedPercent,
                 detail: "\(Fmt.bytes(status.memory?.used)) of \(Fmt.bytes(status.memory?.total))")
            card("Disk", Fmt.percent(status.primaryDisk?.usedPercent), status.primaryDisk?.usedPercent,
                 detail: "\(Fmt.bytes(status.primaryDisk?.free)) free")
            card("Power", Fmt.watts(status.thermal?.systemPower), nil,
                 detail: status.battery.map { "Battery \($0.percent.map { p in "\(p)%" } ?? "—") · \($0.status ?? "—")" } ?? "—")
        }
    }

    private func card(_ label: String, _ value: String, _ percent: Double?, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .medium))
            if percent != nil { MiniBar(percent: percent, height: 5) }
            Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    private func topProcesses(_ status: SystemStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top processes").font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            ForEach(status.processes) { process in
                HStack {
                    Text(process.name ?? "—").font(.system(size: 12)).lineLimit(1)
                    Spacer()
                    Text(Fmt.bytes(process.memoryBytes))
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                    Text(Fmt.percent(process.cpu, decimals: 1))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Severity.forUsage(process.cpu))
                        .frame(width: 58, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }
        }
    }
}
