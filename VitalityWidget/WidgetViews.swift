import SwiftUI
import WidgetKit

struct StatusWidgetView: View {
    var entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if entry.isMissingData {
                MissingDataView()
            } else {
                switch family {
                case .systemSmall:  SmallStatusView(status: entry.status, isStale: entry.isStale)
                case .systemMedium: MediumStatusView(status: entry.status, isStale: entry.isStale)
                default:            LargeStatusView(status: entry.status, isStale: entry.isStale)
                }
            }
        }
        .widgetURL(URL(string: "vitality://dashboard/overview"))
    }
}

/// A widget is already a small surface. A single inset panel gives the three
/// families the same visual grammar as the dashboard without adding nested
/// cards around every value.
private struct WidgetPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ThemeCardBackground(radius: 18))
    }
}

private struct WidgetStatusBadge: View {
    let score: Int?

    private var level: Severity.Level? {
        Severity.level(forHealth: score)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level?.symbolName ?? "questionmark.circle")
                .font(.system(size: 10, weight: .semibold))
            Text(level?.accessibilityLabel ?? "No data")
                .font(Theme.body(11, .medium))
                .lineLimit(1)
        }
        .foregroundStyle(level?.color ?? Theme.inkSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Health status")
        .accessibilityValue(Text(level?.accessibilityLabel ?? "No data"))
    }
}

private struct WidgetMetric: View {
    let label: String
    let value: String
    let percent: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.instrument(10))
                .tracking(1)
                .foregroundStyle(Theme.inkSecondary)
                .textCase(.uppercase)
            Text(value)
                .font(Theme.mono(15, .semibold))
                .foregroundStyle(Severity.forUsage(percent))
                .lineLimit(1)
            MiniBar(percent: percent, height: 4, accessibilityLabel: label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

/// The widget reads a file the app writes. If the app has never run — or was
/// quit — there's nothing to show, and silently rendering zeros would look like
/// a broken widget rather than an idle one.
struct MissingDataView: View {
    var body: some View {
        WidgetPanel {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "gauge.medium")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Text("Open Vitality")
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Vitality needs to run once before this widget can show data.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open Vitality to collect system data")
    }
}

struct StatusFreshnessView: View {
    let collectedAt: Date?
    let isStale: Bool

    init(status: SystemStatus?, isStale: Bool) {
        self.collectedAt = status?.collectedAt
        self.isStale = isStale
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isStale ? "clock" : "checkmark")
                .font(.system(size: 9, weight: .semibold))
            Circle()
                .fill(isStale ? Theme.statusWarn : Theme.statusGood)
                .frame(width: 5, height: 5)
            Text(message)
                .font(Theme.body(10, isStale ? .medium : .regular))
                .foregroundStyle(isStale ? Theme.statusWarn : Theme.inkSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isStale ? "Data is stale" : "Data is current")
        .accessibilityValue(Text(message))
    }

    private var message: String {
        guard collectedAt != nil else { return "Stale · collection time unavailable" }
        let relativeTime = Fmt.relativeTime(from: collectedAt)
        return isStale ? "Stale · collected \(relativeTime)" : "Collected \(relativeTime)"
    }
}

struct SmallStatusView: View {
    let status: SystemStatus?
    let isStale: Bool

    var body: some View {
        WidgetPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("01 HEALTH")
                        .font(Theme.instrument(11, .medium))
                        .tracking(1.5)
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer(minLength: 4)
                    WidgetStatusBadge(score: status?.healthScore)
                }

                HStack(spacing: 11) {
                    ZStack {
                        HealthRing(score: status?.healthScore, lineWidth: 5)
                            .accessibilityHidden(true)
                        Text(status?.healthScore.map(String.init) ?? "—")
                            .font(Theme.mono(18, .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(status?.healthScoreMsg ?? "No data")
                            .font(Theme.body(12, .medium))
                            .foregroundStyle(Severity.forHealth(status?.healthScore))
                            .lineLimit(1)
                        Text("Health score")
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Health score")
                .accessibilityValue(
                    status?.healthScore.map { "\($0) out of 100, \(status?.healthScoreMsg ?? "")" }
                    ?? "No data"
                )

                StatusFreshnessView(status: status, isStale: isStale)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    compactMetric("CPU", status?.cpu?.usage)
                    compactMetric("RAM", status?.memory?.usedPercent)
                    compactMetric("DISK", status?.primaryDisk?.usedPercent)
                }
            }
        }
    }

    private func compactMetric(_ label: String, _ percent: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.instrument(9))
                .tracking(0.8)
                .foregroundStyle(Theme.inkSecondary)
            Text(Fmt.percent(percent))
                .font(Theme.mono(11, .semibold))
                .foregroundStyle(Severity.forUsage(percent))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MediumStatusView: View {
    let status: SystemStatus?
    let isStale: Bool

    var body: some View {
        WidgetPanel {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VITALITY")
                            .font(Theme.instrument(11, .medium))
                            .tracking(1.8)
                            .foregroundStyle(Theme.inkSecondary)
                        Text(status?.hardware?.model ?? status?.host ?? "This Mac")
                            .font(Theme.body(13, .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 5)
                    WidgetStatusBadge(score: status?.healthScore)
                }

                HStack(spacing: 14) {
                    WidgetMetric(label: "CPU", value: Fmt.percent(status?.cpu?.usage), percent: status?.cpu?.usage)
                    WidgetMetric(label: "RAM", value: Fmt.percent(status?.memory?.usedPercent), percent: status?.memory?.usedPercent)
                    WidgetMetric(label: "DISK", value: Fmt.percent(status?.primaryDisk?.usedPercent), percent: status?.primaryDisk?.usedPercent)
                }

                Divider().overlay(Theme.hairline)

                HStack(spacing: 10) {
                    Label(Fmt.watts(status?.headlinePower), systemImage: "bolt.fill")
                    Spacer(minLength: 6)
                    Label("GPU \(Fmt.percent(status?.gpu?.utilization))", systemImage: "cpu.fill")
                    if let battery = status?.battery {
                        Spacer(minLength: 6)
                        Label("\(battery.percent.map { "\($0)%" } ?? "—")", systemImage: "battery.100")
                    }
                }
                .font(Theme.body(10, .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)

                StatusFreshnessView(status: status, isStale: isStale)
            }
        }
    }
}

struct LargeStatusView: View {
    let status: SystemStatus?
    let isStale: Bool

    var body: some View {
        WidgetPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 11) {
                    ZStack {
                        HealthRing(score: status?.healthScore, lineWidth: 6)
                            .accessibilityHidden(true)
                        Text(status?.healthScore.map(String.init) ?? "—")
                            .font(Theme.mono(15, .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(status?.hardware?.model ?? status?.host ?? "This Mac")
                            .font(Theme.body(13, .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text(status?.healthScoreMsg ?? "No data")
                            .font(Theme.body(11, .medium))
                            .foregroundStyle(Severity.forHealth(status?.healthScore))
                            .lineLimit(1)
                        Text("Uptime \(status?.uptime ?? "—")")
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    WidgetStatusBadge(score: status?.healthScore)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Health score")
                .accessibilityValue(
                    status?.healthScore.map { "\($0) out of 100, \(status?.healthScoreMsg ?? "")" }
                    ?? "No data"
                )

                StatusFreshnessView(status: status, isStale: isStale)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 14, alignment: .leading),
                    GridItem(.flexible(), spacing: 14, alignment: .leading),
                ], spacing: 13) {
                    WidgetMetric(label: "CPU", value: Fmt.percent(status?.cpu?.usage), percent: status?.cpu?.usage)
                    WidgetMetric(label: "GPU", value: Fmt.percent(status?.gpu?.utilization), percent: status?.gpu?.utilization)
                    WidgetMetric(label: "RAM", value: Fmt.percent(status?.memory?.usedPercent), percent: status?.memory?.usedPercent)
                    WidgetMetric(label: "DISK", value: Fmt.percent(status?.primaryDisk?.usedPercent), percent: status?.primaryDisk?.usedPercent)
                }

                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                    Text(Fmt.watts(status?.headlinePower))
                        .font(Theme.mono(11, .medium))
                    if let battery = status?.battery {
                        Text("·").foregroundStyle(Theme.inkTertiary)
                        Image(systemName: "battery.100")
                        Text("\(battery.percent.map { "\($0)%" } ?? "—")")
                            .font(Theme.mono(11, .medium))
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)

                if let processes = status?.topProcesses, !processes.isEmpty {
                    Divider().overlay(Theme.hairline)
                    VStack(spacing: 5) {
                        HStack {
                            Text("TOP ACTIVITY")
                                .font(Theme.instrument(10, .medium))
                                .tracking(1.2)
                                .foregroundStyle(Theme.inkSecondary)
                            Spacer()
                            Text("CPU")
                                .font(Theme.instrument(10))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        ForEach(processes.prefix(3)) { process in
                            HStack(spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 4))
                                    .foregroundStyle(Severity.forUsage(process.cpu))
                                Text(process.name ?? "Unknown process")
                                    .font(Theme.body(10))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(Fmt.percent(process.cpu, decimals: 1))
                                    .font(Theme.mono(10, .medium))
                                    .foregroundStyle(Severity.forUsage(process.cpu))
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(process.name ?? "Unknown process")
                            .accessibilityValue("CPU \(Fmt.percent(process.cpu, decimals: 1))")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
