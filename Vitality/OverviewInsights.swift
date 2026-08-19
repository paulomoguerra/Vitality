import SwiftUI

struct OverviewInsight: Identifiable {
    enum Tone {
        case normal, warning, critical

        var color: Color {
            switch self {
            case .normal: return .green
            case .warning: return .orange
            case .critical: return .red
            }
        }

        var icon: String {
            switch self {
            case .normal: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .critical: return "xmark.octagon.fill"
            }
        }
    }

    let id: String
    let tone: Tone
    let title: String
    let detail: String
    let actionTitle: String?
    let actionTab: DashboardTab?
}

enum OverviewInsights {

    @MainActor
    static func evaluate(status: SystemStatus, history: DashboardHistory) -> [OverviewInsight] {
        var result: [OverviewInsight] = []

        if status.healthScore == nil {
            result.append(.init(
                id: "limited-data", tone: .warning,
                title: "Limited data",
                detail: "Vitality cannot evaluate all of the signals needed for a health score.",
                actionTitle: "Open Hardware", actionTab: .sensors
            ))
        }

        if let disk = status.primaryDisk?.usedPercent, disk >= 90 {
            result.append(.init(
                id: "disk-risk", tone: disk >= 95 ? .critical : .warning,
                title: disk >= 95 ? "Disk critically full" : "Disk space is becoming a risk",
                detail: "Only " + Fmt.bytes(status.primaryDisk?.free) + " remains on the primary volume.",
                actionTitle: "Open Storage", actionTab: .storage
            ))
        }

        if let memory = status.memory,
           let used = memory.swapUsed,
           let total = memory.swapTotal,
           total > 0,
           Double(used) / Double(total) >= 0.5 {
            result.append(.init(
                id: "swap-pressure", tone: .warning,
                title: "Memory pressure is high",
                detail: "Your Mac is using " + Fmt.bytes(used) + " of swap. Quitting a heavy app may help.",
                actionTitle: "Open Activity", actionTab: .processes
            ))
        }

        let currentCPU = status.cpu?.usage ?? 0
        let averageCPU = history.average(\.cpu)
        if currentCPU >= 90 || (averageCPU ?? 0) >= 80 {
            result.append(.init(
                id: "cpu-load", tone: currentCPU >= 95 ? .critical : .warning,
                title: "CPU load is sustained",
                detail: "A process may be keeping the system busy. Check the activity table for the cause.",
                actionTitle: "Open Activity", actionTab: .processes
            ))
        }

        if let temperature = status.thermal?.cpu, temperature >= 80 {
            result.append(.init(
                id: "thermal", tone: temperature >= 95 ? .critical : .warning,
                title: "CPU temperature is elevated",
                detail: "The CPU cluster is averaging " + Fmt.celsius(temperature, decimals: 1) + ".",
                actionTitle: "Open Hardware", actionTab: .sensors
            ))
        }

        if result.isEmpty {
            result.append(.init(
                id: "all-clear", tone: .normal,
                title: "No action needed",
                detail: "The monitored signals are within their normal ranges.",
                actionTitle: nil, actionTab: nil
            ))
        }
        return result
    }
}

struct DashboardSparkline: View {
    let values: [Double]
    let scale: MenuBarMetric.Reading.Scale
    let tint: Color

    var body: some View {
        if values.count > 1 {
            MenuBarSparkline(samples: values, scale: scale, tint: tint)
        } else {
            Capsule().fill(Color.secondary.opacity(0.16))
        }
    }
}

struct OverviewInsightRow: View {
    let insight: OverviewInsight
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: insight.tone.icon)
                .foregroundStyle(insight.tone.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.system(size: 12, weight: .medium))
                Text(insight.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let action, let actionTitle = insight.actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(insight.tone.color.opacity(0.08)))
    }
}

struct OverviewMetricCard: View {
    let label: String
    let value: String
    let detail: String
    let values: [Double]
    let scale: MenuBarMetric.Reading.Scale
    let tint: Color
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(value)
                .font(.system(size: 25, weight: .semibold).monospacedDigit())
            DashboardSparkline(values: values, scale: scale, tint: tint)
                .frame(height: 18)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(action == nil ? Color.clear : tint.opacity(0.18)))
    }
}
