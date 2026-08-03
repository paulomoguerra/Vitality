import SwiftUI
import WidgetKit

struct StatusWidgetView: View {
    var entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.isMissingData {
            MissingDataView()
        } else {
            switch family {
            case .systemSmall:  SmallStatusView(status: entry.status)
            case .systemMedium: MediumStatusView(status: entry.status)
            default:            LargeStatusView(status: entry.status)
            }
        }
    }
}

/// The widget reads a file the app writes. If the app has never run — or was
/// quit — there's nothing to show, and silently rendering zeros would look like
/// a broken widget rather than an idle one.
struct MissingDataView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.medium")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Text("Open Vitality")
                .font(.system(size: 12, weight: .medium))
            Text("The app needs to run to collect data.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
    }
}

struct SmallStatusView: View {
    let status: SystemStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Health").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "gauge.medium")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                HealthRing(score: status?.healthScore)
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text(status?.healthScore.map(String.init) ?? "—")
                        .font(.system(size: 19, weight: .medium))
                    Text(status?.healthScoreMsg ?? "—")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                miniStat("cpu", status?.cpu?.usage)
                miniStat("memorychip", status?.memory?.usedPercent)
                miniStat("internaldrive", status?.primaryDisk?.usedPercent)
            }
        }
        .padding(14)
    }

    private func miniStat(_ icon: String, _ percent: Double?) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 8))
            Text(Fmt.percent(percent)).font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(Severity.forUsage(percent))
    }
}

struct MediumStatusView: View {
    let status: SystemStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(status?.hardware?.model ?? status?.host ?? "This Mac")
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(Severity.forHealth(status?.healthScore))
                        .frame(width: 7, height: 7)
                    Text("\(status?.healthScore.map(String.init) ?? "—") · \(status?.healthScoreMsg ?? "—")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                stat("CPU", status?.cpu?.usage)
                stat("Memory", status?.memory?.usedPercent)
                stat("Disk", status?.primaryDisk?.usedPercent)
            }

            HStack {
                Label(Fmt.watts(status?.thermal?.systemPower), systemImage: "bolt.fill")
                if let gpu = status?.measuredGPU, gpu.utilization != nil {
                    Spacer()
                    Label("GPU \(Fmt.percent(gpu.utilization))", systemImage: "cpu.fill")
                }
                Spacer()
                if let battery = status?.battery {
                    Label("\(battery.percent.map { "\($0)%" } ?? "—")", systemImage: "battery.100")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private func stat(_ label: String, _ percent: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text(Fmt.percent(percent)).font(.system(size: 10, weight: .medium))
            }
            MiniBar(percent: percent)
        }
    }
}

struct LargeStatusView: View {
    let status: SystemStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                // Score inside the ring, matching the dashboard header — the
                // ring alone was decorative and the number lived in the
                // subtitle, so the two surfaces read differently.
                ZStack {
                    HealthRing(score: status?.healthScore, lineWidth: 6)
                    Text(status?.healthScore.map(String.init) ?? "—")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(status?.hardware?.model ?? status?.host ?? "This Mac")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(status?.healthScoreMsg ?? "—")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Severity.forHealth(status?.healthScore))
                        .lineLimit(1)
                    Text("Up \(status?.uptime ?? "—")")
                        .font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            // `alignment: .leading` is load-bearing: GridItem centres cell
            // content by default. The four bar metrics fill their cell so they
            // looked fine, but any narrower cell drifted to the middle.
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 14, alignment: .leading),
                GridItem(.flexible(), spacing: 14, alignment: .leading),
            ], spacing: 13) {
                metric("CPU", Fmt.percent(status?.cpu?.usage), status?.cpu?.usage,
                       sub: "\(status?.cpu?.coreCount.map(String.init) ?? "—") cores")
                metric("GPU", Fmt.percent(status?.measuredGPU?.utilization),
                       status?.measuredGPU?.utilization,
                       sub: status?.measuredGPU?.inUseMemory.map { "\(Fmt.bytes($0)) used" } ?? "—")
                metric("Memory", Fmt.percent(status?.memory?.usedPercent), status?.memory?.usedPercent,
                       sub: "\(Fmt.bytes(status?.memory?.used)) used")
                metric("Disk", Fmt.percent(status?.primaryDisk?.usedPercent), status?.primaryDisk?.usedPercent,
                       sub: "\(Fmt.bytes(status?.primaryDisk?.free)) free")
            }

            // Power has no percentage, so it can't carry a bar like the four
            // above. As a fifth grid cell it sat alone next to a dead hole.
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill").font(.system(size: 9))
                Text(Fmt.watts(status?.thermal?.systemPower))
                    .font(.system(size: 11, weight: .medium))
                if let battery = status?.battery {
                    Text("·").foregroundStyle(.tertiary)
                    Image(systemName: "battery.100").font(.system(size: 9))
                    Text("\(battery.percent.map { "\($0)%" } ?? "—") \(battery.status ?? "")")
                        .font(.system(size: 11, weight: .medium))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)

            if let processes = status?.topProcesses, !processes.isEmpty {
                Divider()
                VStack(spacing: 3) {
                    ForEach(processes.prefix(3)) { process in
                        HStack {
                            Text(process.name ?? "—").font(.system(size: 10)).lineLimit(1)
                            Spacer()
                            Text(Fmt.percent(process.cpu, decimals: 1))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Severity.forUsage(process.cpu))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func metric(_ label: String, _ value: String, _ percent: Double?, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .semibold))
            // Always drawn, even when the value is missing. Conditionally
            // omitting the bar makes that cell shorter than its neighbour and
            // knocks the whole grid row out of alignment.
            MiniBar(percent: percent)
            Text(sub).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
