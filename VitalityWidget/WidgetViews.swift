import SwiftUI
import WidgetKit

struct StatusWidgetView: View {
    var entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallStatusView(status: entry.status)
        case .systemMedium:
            MediumStatusView(status: entry.status)
        default:
            LargeStatusView(status: entry.status)
        }
    }
}

private func barColor(_ percent: Double) -> Color {
    if percent >= 85 { return .red }
    if percent >= 60 { return .orange }
    return .green
}

private func healthColor(_ score: Int) -> Color {
    if score >= 80 { return .green }
    if score >= 50 { return .orange }
    return .red
}

private struct MiniBar: View {
    let percent: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(barColor(percent))
                    .frame(width: geo.size.width * CGFloat(min(max(percent, 0), 100) / 100))
            }
        }
        .frame(height: 4)
    }
}

struct SmallStatusView: View {
    let status: SystemStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Health").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "cpu").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: CGFloat(status?.healthScore ?? 0) / 100)
                        .stroke(healthColor(status?.healthScore ?? 0), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(status?.healthScore ?? 0)").font(.system(size: 18, weight: .medium))
                    Text(status?.healthScoreMsg ?? "—").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(status?.host ?? "Mac").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
    }
}

struct MediumStatusView: View {
    let status: SystemStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mac status").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(status?.healthScore ?? 0) · \(status?.healthScoreMsg ?? "—")")
                    .font(.system(size: 11))
                    .foregroundStyle(healthColor(status?.healthScore ?? 0))
            }
            HStack(spacing: 16) {
                stat(label: "CPU", value: String(format: "%.0f%%", status?.cpu.usage ?? 0), percent: status?.cpu.usage ?? 0)
                stat(label: "Memory", value: String(format: "%.0f%%", status?.memory.usedPercent ?? 0), percent: status?.memory.usedPercent ?? 0)
                stat(label: "Disk", value: String(format: "%.0f%%", status?.primaryDisk?.usedPercent ?? 0), percent: status?.primaryDisk?.usedPercent ?? 0)
            }
        }
        .padding(14)
    }

    private func stat(label: String, value: String, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.system(size: 10, weight: .medium))
            }
            MiniBar(percent: percent)
        }
    }
}

struct LargeStatusView: View {
    let status: SystemStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(status?.host ?? "Mac").font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
                Text("\(status?.healthScore ?? 0) \(status?.healthScoreMsg ?? "—")")
                    .font(.system(size: 11))
                    .foregroundStyle(healthColor(status?.healthScore ?? 0))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                metric(label: "CPU · \(status?.cpu.coreCount ?? 0) cores",
                       value: String(format: "%.0f%%", status?.cpu.usage ?? 0),
                       percent: status?.cpu.usage ?? 0)
                metric(label: "Memory",
                       value: String(format: "%.0f%%", status?.memory.usedPercent ?? 0),
                       percent: status?.memory.usedPercent ?? 0)
                metric(label: "Disk",
                       value: String(format: "%.0f%%", status?.primaryDisk?.usedPercent ?? 0),
                       percent: status?.primaryDisk?.usedPercent ?? 0)
                metric(label: "Power",
                       value: String(format: "%.0fW", status?.thermal.systemPower ?? 0),
                       percent: status?.battery.map { Double($0.percent) } ?? 0)
            }

            if let proc = status?.topProcess {
                Divider()
                HStack {
                    Text("Top process").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(proc.name) · \(String(format: "%.0f%%", proc.cpu))").font(.system(size: 10))
                }
            }
        }
        .padding(16)
    }

    private func metric(label: String, value: String, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .medium))
            MiniBar(percent: percent)
        }
    }
}
