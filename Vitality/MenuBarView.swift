import SwiftUI

/// Which pane the popover is showing. A plain enum rather than NavigationStack
/// because popovers size themselves to their content, and NavigationStack's
/// animated push makes the window jump around while resizing.
enum MenuPane: Hashable {
    case root, cpu, gpu, memory, storage, power, processes, menuBar, thermal, support
}

struct MenuBarView: View {
    @ObservedObject var poller: StatusPoller
    @ObservedObject var settings: MenuBarSettings
    @ObservedObject var history: MenuBarHistory
    @ObservedObject var alerts: AlertCenter
    @State private var pane: MenuPane = .root

    var onOpenDashboard: (DashboardSection?) -> Void
    var onOpenSettings: () -> Void = {}
    var onOpenAlert: ((AlertRuleID) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch pane {
            case .root:       rootPane
            case .cpu:        CPUDetailPane(status: poller.latest, back: goBack)
            case .gpu:        GPUDetailPane(status: poller.latest, back: goBack)
            case .memory:     MemoryDetailPane(status: poller.latest, back: goBack)
            case .storage:    StorageDetailPane(status: poller.latest, back: goBack,
                                                openDashboard: { openDashboard(.storage) })
            case .power:      PowerDetailPane(status: poller.latest, back: goBack)
            case .processes:  ProcessesDetailPane(status: poller.latest, back: goBack,
                                                  openDashboard: { openDashboard(.activity) })
            case .menuBar:    MenuBarSettingsPane(settings: settings, history: history,
                                                  status: poller.latest, back: goBack)
            case .thermal:    ThermalDetailPane(status: poller.latest, back: goBack,
                                                openDashboard: { openDashboard(.sensors) })
            case .support:    SupportPane(back: goBack)
            }
        }
        .frame(width: 344)
        .background(Theme.bg)
        .padding(.vertical, 8)
    }

    private func goBack() { pane = .root }

    private func openDashboard(_ section: DashboardSection? = nil) {
        onOpenDashboard(section)
    }

    // MARK: - Root

    @ViewBuilder
    private var rootPane: some View {
        if let status = poller.latest {
            VStack(alignment: .leading, spacing: 12) {
                healthHero(status: status)
                vitalGrid(status: status)
                topProcess(status: status)
                footer(status: status)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Collecting system status")
                            .font(Theme.mono(13, .medium))
                        Text("The first reading takes a moment.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(ThemeCardBackground(radius: Theme.nestedRadius))
                footer(status: nil)
            }
        }
    }

    private func healthHero(status: SystemStatus) -> some View {
        let health = MenuHealthPresentation(status: status, alerts: alerts.active)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: health.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(health.color)
                    .frame(width: 38, height: 38)
                    .background(health.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("System status")
                        .font(Theme.mono(9, .medium))
                        .tracking(1.4)
                        .foregroundStyle(Theme.inkSecondary)
                        .textCase(.uppercase)
                    Text(health.title)
                        .font(Theme.mono(19, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(health.message)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(health.scoreText)
                        .font(Theme.mono(24, .semibold))
                        .foregroundStyle(health.color)
                    Text("health")
                        .font(Theme.mono(9, .medium))
                        .tracking(1)
                        .foregroundStyle(Theme.inkTertiary)
                        .textCase(.uppercase)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Health score")
                .accessibilityValue(health.scoreText)
            }

            if let action = health.action {
                Button(action.title) {
                    if let rule = action.alert, let onOpenAlert {
                        onOpenAlert(rule)
                    } else {
                        pane = action.destination
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.small)
                .accessibilityHint(action.alert == nil
                                   ? "Opens the related Vitality view"
                                   : "Opens the dashboard area that can help resolve this alert")
            }
        }
        .padding(16)
        .background(ThemeCardBackground(radius: Theme.nestedRadius))
        .accessibilityElement(children: .contain)
    }

    private func vitalGrid(status: SystemStatus) -> some View {
        let cells: [CompactVitalCell.Configuration] = [
            .init(metric: .cpu, value: Fmt.percent(status.cpu?.usage, decimals: 1), tint: Severity.forUsage(status.cpu?.usage), pane: .cpu),
            .init(metric: .gpu, value: Fmt.percent(status.gpu?.utilization, decimals: 1), tint: Severity.forUsage(status.gpu?.utilization), pane: .gpu),
            .init(metric: .memory, value: Fmt.percent(status.memory?.usedPercent, decimals: 1), tint: Severity.forUsage(status.memory?.usedPercent), pane: .memory),
            .init(metric: .disk, value: Fmt.percent(status.primaryDisk?.usedPercent), tint: Severity.forUsage(status.primaryDisk?.usedPercent), pane: .storage),
            .init(metric: .power, value: Fmt.watts(status.headlinePower), tint: Theme.ink, pane: .power),
            .init(metric: .cpuTemp, value: Fmt.celsius(status.thermal?.cpu, decimals: 1), tint: Severity.level(forTemperature: status.thermal?.cpu)?.color ?? Theme.ink, pane: .thermal)
        ]

        return VStack(alignment: .leading, spacing: 7) {
            Text("Live readings")
                .font(Theme.mono(9, .medium))
                .tracking(1.4)
                .foregroundStyle(Theme.inkSecondary)
                .textCase(.uppercase)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(cells) { cell in
                    CompactVitalCell(configuration: cell) { pane = cell.pane }
                }
            }
        }
    }

    @ViewBuilder
    private func topProcess(status: SystemStatus) -> some View {
        if let process = status.topProcess {
            Button { pane = .processes } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .foregroundStyle(Theme.accent)
                        .font(.system(size: 16))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Top process")
                            .font(Theme.mono(9, .medium))
                            .tracking(1.2)
                            .foregroundStyle(Theme.inkSecondary)
                            .textCase(.uppercase)
                        Text(process.name ?? "Unknown process")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(Fmt.percent(process.cpu, decimals: 1))
                        .font(Theme.mono(13, .medium))
                        .foregroundStyle(Severity.forUsage(process.cpu))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(ThemeCardBackground(radius: Theme.nestedRadius))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Top process \(process.name ?? "Unknown process")")
            .accessibilityValue(Fmt.percent(process.cpu, decimals: 1))
        }
    }

    @ViewBuilder
    private func footer(status: SystemStatus?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuActionRow(icon: "square.grid.2x2", label: "Open dashboard…", action: { openDashboard(nil) })
            MenuActionRow(icon: "gearshape", label: "Open settings…", action: onOpenSettings)
            MenuActionRow(icon: "info.circle", label: "About Vitality") { pane = .support }
            MenuActionRow(icon: "power", label: "Quit Vitality") { NSApp.terminate(nil) }

            if let status {
                Text("\(status.host ?? "This Mac") · updated \(Fmt.relativeTime(from: status.collectedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .lineLimit(1)
            }
        }
    }
}

/// Pure presentation logic for the popover hero. Keeping the judgement in a
/// value type makes the most important copy easy to test without launching the
/// menu bar app.
struct MenuHealthPresentation {
    struct Action {
        let title: String
        let destination: MenuPane
        var alert: AlertRuleID? = nil
    }

    let title: String
    let message: String
    let scoreText: String
    let icon: String
    let color: Color
    let action: Action?

    init(status: SystemStatus, alert: ActiveAlert? = nil) {
        self.init(status: status, alerts: alert.map { [$0] } ?? [])
    }

    init(status: SystemStatus, alerts: [ActiveAlert]) {
        let score = status.healthScore
        scoreText = score.map(String.init) ?? "—"

        if let alert = alerts.first {
            title = alert.title
            message = alert.detail
            icon = alert.severity.symbolName
            color = alert.severity.color
            // Keep the most severe alert's copy. If that row has no
            // destination, use the first alert that does so the CTA
            // still goes somewhere useful.
            action = Self.cta(for: alerts.first(where: { $0.action != .none }))
            return
        }

        color = Severity.forHealth(score)

        switch score {
        case let value? where value >= 90:
            title = "All clear"
            message = "Everything is within normal range."
            icon = "checkmark.circle.fill"
        case let value? where value >= 75:
            title = "Running well"
            message = status.healthScoreMsg?.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init)
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? "A small pressure signal is worth watching."
            icon = "checkmark.circle.fill"
        case let value? where value >= 55:
            title = "Needs attention"
            message = Self.issueMessage(status) ?? "One or more readings need attention."
            icon = "exclamationmark.triangle.fill"
        case .some:
            title = "Under pressure"
            message = Self.issueMessage(status) ?? "Review the current system pressure."
            icon = "exclamationmark.octagon.fill"
        case .none:
            title = "Collecting data"
            message = "Waiting for enough readings to assess this Mac."
            icon = "waveform.path.ecg"
        }

        // One primary action only. Prefer the highest-signal path and leave
        // secondary detail views in the grid below.
        if let disk = status.primaryDisk?.usedPercent, disk >= 85 {
            action = Action(title: "Review storage", destination: .storage)
        } else if let process = status.topProcess, (process.cpu ?? 0) >= 75 {
            action = Action(title: "Review activity", destination: .processes)
        } else if let swap = status.memory?.swapUsed,
                  let total = status.memory?.swapTotal,
                  total > 0,
                  Double(swap) / Double(total) >= 0.45 {
            action = Action(title: "Review memory", destination: .memory)
        } else if let temperature = status.thermal?.cpu, temperature >= 80 {
            action = Action(title: "Review temperature", destination: .thermal)
        } else {
            action = nil
        }
    }

    private static func cta(for alert: ActiveAlert?) -> Action? {
        guard let alert else { return nil }
        switch alert.action {
        case .openStorage:
            return Action(title: alert.actionLabel ?? "Review storage", destination: .storage, alert: alert.id)
        case .openActivity:
            return Action(title: alert.actionLabel ?? "Review activity", destination: .processes, alert: alert.id)
        case .openSensors:
            return Action(title: alert.actionLabel ?? "Review sensors", destination: .thermal, alert: alert.id)
        case .openPower:
            return Action(title: alert.actionLabel ?? "Review power", destination: .power, alert: alert.id)
        case .none:
            return nil
        }
    }

    private static func issueMessage(_ status: SystemStatus) -> String? {
        guard let message = status.healthScoreMsg,
              let detail = message.split(separator: ":", maxSplits: 1).dropFirst().first else { return nil }
        return String(detail).trimmingCharacters(in: .whitespaces)
    }
}

private struct CompactVitalCell: View {
    struct Configuration: Identifiable {
        let metric: MenuBarMetric
        let value: String
        let tint: Color
        let pane: MenuPane

        var id: MenuBarMetric { metric }
    }

    let configuration: Configuration
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: configuration.metric.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(configuration.tint)
                    Text(configuration.metric.shortLabel)
                        .font(Theme.mono(9, .medium))
                        .tracking(1)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Text(configuration.value)
                    .font(Theme.mono(17, .medium))
                    .foregroundStyle(configuration.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(ThemeCardBackground(radius: Theme.nestedRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(configuration.metric.label)
        .accessibilityValue(configuration.value)
    }
}

// MARK: - Row primitives

/// A metric row. Rows with an `action` get a chevron and hover highlight;
/// rows without one are plain readouts, so the affordance matches reality.
struct MenuRow: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = .secondary
    var action: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        if let action {
            Button(action: action) { rowBody(showChevron: true) }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
        } else {
            rowBody(showChevron: false)
        }
    }

    private func rowBody(showChevron: Bool) -> some View {
        HStack(spacing: 0) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(label).font(.system(size: 12))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 5)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 32)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering && showChevron ? Color.primary.opacity(0.07) : .clear)
                .padding(.horizontal, 7)
        )
        .contentShape(Rectangle())
    }
}

struct MenuActionRow: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(label).font(.system(size: 12))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.primary.opacity(0.07) : .clear)
                    .padding(.horizontal, 7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 32, alignment: .leading)
        .onHover { hovering = $0 }
    }
}

/// Shared header for every detail pane — title plus a back affordance.
struct PaneHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        Button(action: back) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 32, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

/// Label/value line used inside detail panes.
struct DetailLine: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2.5)
    }
}
