import SwiftUI

/// The dashboard keeps five stable destinations. Network belongs to Activity,
/// alert state belongs to Overview, and alert configuration belongs to Settings.
enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case overview = "Overview"
    case activity = "Activity"
    case storage = "Storage"
    case power = "Power"
    case sensors = "Sensors"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "gauge.medium"
        case .activity: return "list.bullet.rectangle"
        case .storage:  return "internaldrive"
        case .power:    return "bolt.fill"
        case .sensors:  return "thermometer.medium"
        }
    }
}

struct DashboardView: View {
    @ObservedObject var poller: StatusPoller
    let history: MetricsHistoryStore
    @ObservedObject var alerts: AlertCenter
    @ObservedObject var router: DashboardRouter

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(DashboardSection.allCases) { item in
                    Button {
                        router.open(item)
                    } label: {
                        sidebarRow(item)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.sidebarBg)
            .navigationSplitViewColumnWidth(min: 170, ideal: 185, max: 220)
        } detail: {
            Group {
                switch router.section {
                case .overview:
                    OverviewPane(poller: poller, history: history, alerts: alerts,
                                 openSection: router.open,
                                 openAlert: router.open(alert:))
                case .activity:
                    ActivityPane(poller: poller, history: history,
                                 initialProcessSort: router.processSort,
                                 mode: $router.activityMode)
                        .id(router.processSort)
                case .storage:
                    StorageView(poller: poller, mode: $router.storageMode)
                case .power:    PowerPane(poller: poller, history: history)
                case .sensors:  SensorsView(poller: poller)
                }
            }
            .padding(Theme.pagePadding)
            .frame(minWidth: 560)
            .background(Theme.pageBg)
        }
        .background(Theme.pageBg)
        .preferredColorScheme(.dark)
        .frame(minWidth: 760, minHeight: 500)
    }

    private func sidebarRow(_ item: DashboardSection) -> some View {
        let selected = router.section == item
        let badge = item == .overview ? alerts.active.count : 0
        return HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Theme.accent : Theme.inkDim)
                .themeIconWell(size: 28, selected: selected)
            Text(item.rawValue)
                .font(Theme.mono(11, .medium))
                .foregroundStyle(selected ? Theme.ink : Theme.inkDim)
            Spacer(minLength: 4)
            if badge > 0 {
                Text("\(badge)")
                    .font(Theme.mono(10, .semibold))
                    .foregroundStyle(Theme.inkDim)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.sidebarItemRadius, style: .continuous)
                .fill(selected ? Theme.accentSoft : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(item.rawValue)
        .accessibilityValue(badge > 0 ? "\(badge) alerts" : "")
    }
}

// MARK: - Overview

struct OverviewPane: View {
    @ObservedObject var poller: StatusPoller
    @ObservedObject var history: MetricsHistoryStore
    @ObservedObject var alerts: AlertCenter
    let openSection: (DashboardSection) -> Void
    let openAlert: (AlertRuleID) -> Void

    @State private var range: HistoryRange = .day

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionGap) {
                if let status = poller.latest {
                    header(status)
                    healthCard(status)
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

    private func header(_ status: SystemStatus) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VITALITY")
                    .font(Theme.mono(22, .semibold))
                    .foregroundStyle(Theme.ink)
                Text("MAC VITAL SIGNS")
                    .font(Theme.mono(10))
                    .tracking(3)
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
            HStack(spacing: 14) {
                livePill(status)
                OverviewRangePills(range: $range)
            }
            .padding(.top, 6)
        }
    }

    private func livePill(_ status: SystemStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: liveIcon(status))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(liveColor(status))
            Text(liveLabel(status))
                .font(Theme.mono(10, .medium))
                .tracking(1)
                .foregroundStyle(Theme.inkDim)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Data status")
        .accessibilityValue(liveLabel(status))
    }

    private func liveColor(_ status: SystemStatus) -> Color {
        switch StatusFreshness.state(collectedAt: status.collectedAt) {
        case .live:    return Theme.ok
        case .stale:   return Theme.statusWarn
        case .unknown: return Theme.inkDim
        }
    }

    private func liveLabel(_ status: SystemStatus) -> String {
        switch StatusFreshness.state(collectedAt: status.collectedAt) {
        case .live: return "LIVE"
        case .stale:
            return "STALE · \(Fmt.relativeTime(from: status.collectedAt))"
        case .unknown: return "WAITING FOR TIME"
        }
    }

    private func liveIcon(_ status: SystemStatus) -> String {
        switch StatusFreshness.state(collectedAt: status.collectedAt) {
        case .live:    return "circle.fill"
        case .stale:   return "clock.badge.exclamationmark.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private func healthCard(_ status: SystemStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ThemeCardHeader(number: "01", title: "HEALTH",
                            trailing: healthTrailing(status),
                            trailingColor: Severity.forHealth(status.healthScore))
            HStack(spacing: 20) {
                OverviewHealthRing(score: status.healthScore)
                    .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 8) {
                    Text(alerts.active.first?.title ?? statusTitle(status))
                        .font(Theme.body(17, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(alerts.active.first?.detail ?? status.healthScoreMsg ?? "Limited data")
                        .font(Theme.body(12))
                        .foregroundStyle(alerts.active.first.map { $0.severity.color }
                                         ?? Severity.forHealth(status.healthScore))
                        .lineLimit(3)
                    Text(hardwareLine(status))
                        .font(Theme.mono(9))
                        .tracking(0.6)
                        .foregroundStyle(Theme.inkFaint)
                        .lineLimit(2)

                    HStack(spacing: 18) {
                        ThemeStat(label: "CPU NOW",
                                  value: Fmt.percent(status.cpu?.usage),
                                  color: Theme.slotCPU)
                        ThemeStat(label: "POWER",
                                  value: Fmt.watts(status.headlinePower),
                                  color: Theme.ink)
                        ThemeStat(label: "DISK FREE",
                                  value: Fmt.bytes(status.primaryDisk?.free),
                                  color: Theme.slotDisk)
                    }
                    .padding(.top, 4)

                    if let alert = alerts.active.first(where: { $0.actionLabel != nil }),
                       let label = alert.actionLabel {
                        Button(label) { openAlert(alert.id) }
                            .buttonStyle(ThemePillButtonStyle(prominent: true))
                            .accessibilityHint("Opens the area that can help resolve this alert")
                            .padding(.top, 4)
                    } else if alerts.active.isEmpty {
                        Label("No action needed", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.ok)
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .themeCard()
    }

    private func hardwareLine(_ status: SystemStatus) -> String {
        ([status.hardware?.model ?? status.host,
          status.hardware?.chip,
          status.hardware?.totalRAM.map { Fmt.bytes($0) },
          status.hardware?.osVersion]
            .compactMap { $0 }
            .joined(separator: " · ")
         + " · UP \(status.uptime ?? "—")").uppercased()
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

    private func healthTrailing(_ status: SystemStatus) -> String {
        guard let score = status.healthScore else { return "—" }
        switch score {
        case 90...: return "OK"
        case 75..<90: return "GOOD"
        case 55..<75: return "FAIR"
        default: return "LOW"
        }
    }

    @ViewBuilder
    private var alertList: some View {
        if !alerts.active.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ThemeCardHeader(
                    number: "02", title: "ACTIVE ALERTS",
                    trailing: "\(alerts.active.count)",
                    trailingColor: Theme.accent
                )
                VStack(spacing: 7) {
                    ForEach(alerts.active) { alert in
                        AlertCard(alert: alert) {
                            openAlert(alert.id)
                        } snooze: {
                            alerts.snooze(alert.id)
                        }
                    }
                }
            }
            .themeCard()
        }
    }

    private func metrics(_ status: SystemStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ThemeCardHeader(number: alerts.active.isEmpty ? "02" : "03", title: "METRICS")
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Theme.gridGap, alignment: .top),
                GridItem(.flexible(), spacing: Theme.gridGap, alignment: .top),
            ], spacing: Theme.gridGap) {
                HistoryChartCard(
                    label: "CPU",
                    currentText: Fmt.percent(status.cpu?.usage, decimals: 1),
                    subtitle: "\(status.cpu?.coreCount.map(String.init) ?? "—") cores · load \(Fmt.load(status.cpu?.load1))",
                    points: history.series(.cpu, range: range),
                    scale: .percent, tint: Theme.slotCPU,
                    accessibilityRange: range.label,
                    stats: history.stats(.cpu, range: range),
                    showsCalendarDate: range.showsCalendarDate,
                    action: { openSection(.activity) }
                )

                HistoryChartCard(
                    label: "GPU",
                    currentText: Fmt.percent(status.gpu?.utilization, decimals: 1),
                    subtitle: status.gpu?.inUseMemory.map { Fmt.bytes($0) + " in use" } ?? "No GPU data",
                    points: history.series(.gpu, range: range),
                    scale: .percent, tint: Theme.slotGPU,
                    accessibilityRange: range.label,
                    stats: history.stats(.gpu, range: range),
                    showsCalendarDate: range.showsCalendarDate
                )

                HistoryChartCard(
                    label: "MEMORY",
                    currentText: Fmt.percent(status.memory?.usedPercent, decimals: 1),
                    subtitle: Fmt.bytes(status.memory?.used) + " of " + Fmt.bytes(status.memory?.total),
                    points: history.series(.memory, range: range),
                    scale: .percent, tint: Theme.slotRAM,
                    accessibilityRange: range.label,
                    stats: history.stats(.memory, range: range),
                    showsCalendarDate: range.showsCalendarDate,
                    action: { openSection(.activity) }
                )

                HistoryChartCard(
                    label: "DISK",
                    currentText: Fmt.percent(status.primaryDisk?.usedPercent),
                    subtitle: Fmt.bytes(status.primaryDisk?.free) + " free",
                    points: history.series(.disk, range: range),
                    scale: .percent, tint: Theme.slotDisk,
                    accessibilityRange: range.label,
                    stats: history.stats(.disk, range: range),
                    showsCalendarDate: range.showsCalendarDate,
                    action: { openSection(.storage) }
                )
            }
        }
    }

    private func activity(_ status: SystemStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(alerts.active.isEmpty ? "03" : "04")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.inkFaint)
                Text("ACTIVITY")
                    .font(Theme.mono(10, .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.inkDim)
                Spacer()
                Button("OPEN →") { openSection(.activity) }
                    .buttonStyle(.plain)
                    .font(Theme.mono(10, .medium))
                    .tracking(1)
                    .foregroundStyle(Theme.accent)
            }
            .textCase(.uppercase)

            ForEach(status.processes.prefix(3)) { process in
                HStack {
                    Text(process.name ?? "—")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(Fmt.bytes(process.memoryBytes))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.inkFaint)
                    Text(Fmt.percent(process.cpu, decimals: 1))
                        .font(Theme.mono(12, .medium))
                        .foregroundStyle(Severity.forUsage(process.cpu))
                        .frame(width: 58, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }

            if status.processes.isEmpty {
                Text("NO PROCESS DATA")
                    .font(Theme.mono(11))
                    .tracking(1)
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .themeCard()
    }
}

/// Dotted instrument ring — Cochicho-style count-in-a-ring for the health score.
private struct OverviewHealthRing: View {
    let score: Int?

    var body: some View {
        let progress = Double(min(max(score ?? 0, 0), 100)) / 100
        let active = Severity.forHealth(score)
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let ringRadius = min(size.width, size.height) / 2 - 6
                let dots = 48
                for i in 0..<dots {
                    let angle = Double(i) / Double(dots) * 2 * .pi - .pi / 2
                    let point = CGPoint(
                        x: center.x + cos(angle) * ringRadius,
                        y: center.y + sin(angle) * ringRadius
                    )
                    let lit = Double(i) / Double(dots) < progress
                    let rect = CGRect(x: point.x - 1.6, y: point.y - 1.6, width: 3.2, height: 3.2)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(lit ? active : Color.white.opacity(0.12))
                    )
                }
            }
            VStack(spacing: 2) {
                Text(score.map(String.init) ?? "—")
                    .font(Theme.mono(26, .medium))
                    .foregroundStyle(Theme.ink)
                Text("SCORE")
                    .font(Theme.mono(9))
                    .tracking(1.5)
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vitality score")
        .accessibilityValue(score.map { "\($0) out of 100" } ?? "Unavailable")
    }
}

/// Orange/dark pills for the history window, matching Cochicho segment chips.
private struct OverviewRangePills: View {
    @Binding var range: HistoryRange

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HistoryRange.allCases) { item in
                Button {
                    range = item
                } label: {
                    Text(item.label.uppercased())
                        .font(Theme.mono(10, .medium))
                        .tracking(1)
                        .foregroundStyle(range == item ? Color.black : Theme.inkDim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(range == item ? Theme.accent : Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .frame(minHeight: 28)
                .accessibilityLabel("Show \(item.label) of history")
                .accessibilityAddTraits(range == item ? .isSelected : [])
            }
        }
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
                .foregroundStyle(alert.severity == .critical ? Theme.accent : Theme.statusWarn)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(Theme.mono(11, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(alert.detail)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.inkDim)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let label = alert.actionLabel {
                Button(label, action: action)
                    .buttonStyle(ThemePillButtonStyle())
            }
            Button("Snooze", action: snooze)
                .buttonStyle(.plain)
                .font(Theme.mono(10, .medium))
                .tracking(1)
                .foregroundStyle(Theme.inkFaint)
                .help("Hide this alert and its notifications for 6 hours")
                .accessibilityLabel("Snooze \(alert.title) for 6 hours")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.alertRadius, style: .continuous)
                .fill(Theme.chipFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.alertRadius, style: .continuous)
                        .stroke(alert.severity == .critical
                                ? Theme.accent.opacity(0.35)
                                : Theme.statusWarn.opacity(0.35), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
    }
}
