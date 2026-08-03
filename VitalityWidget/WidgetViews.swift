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
            HStack(spacing: 10) {
                HealthRing(score: status?.healthScore, lineWidth: 6)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(status?.hardware?.model ?? status?.host ?? "This Mac")
                        .font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text("\(status?.healthScore.map(String.init) ?? "—") · \(status?.healthScoreMsg ?? "—") · up \(status?.uptime ?? "—")")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metric("CPU", Fmt.percent(status?.cpu?.usage), status?.cpu?.usage,
                       sub: "\(status?.cpu?.coreCount.map(String.init) ?? "—") cores")
                metric("Memory", Fmt.percent(status?.memory?.usedPercent), status?.memory?.usedPercent,
                       sub: Fmt.bytes(status?.memory?.used))
                metric("Disk", Fmt.percent(status?.primaryDisk?.usedPercent), status?.primaryDisk?.usedPercent,
                       sub: "\(Fmt.bytes(status?.primaryDisk?.free)) free")
                metric("Power", Fmt.watts(status?.thermal?.systemPower), nil,
                       sub: status?.battery.map { "Battery \($0.percent.map { p in "\(p)%" } ?? "—")" } ?? "—")
            }

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
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .medium))
            if percent != nil { MiniBar(percent: percent) }
            Text(sub).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
        }
    }
}
