import SwiftUI

/// Which pane the popover is showing. A plain enum rather than NavigationStack
/// because popovers size themselves to their content, and NavigationStack's
/// animated push makes the window jump around while resizing.
enum MenuPane: Hashable {
    case root, cpu, gpu, memory, storage, power, processes
}

struct MenuBarView: View {
    @ObservedObject var poller: StatusPoller
    @State private var pane: MenuPane = .root

    var onOpenDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch pane {
            case .root:       rootPane
            case .cpu:        CPUDetailPane(status: poller.latest, back: goBack)
            case .gpu:        GPUDetailPane(status: poller.latest, back: goBack)
            case .memory:     MemoryDetailPane(status: poller.latest, back: goBack)
            case .storage:    StorageDetailPane(status: poller.latest, back: goBack,
                                                openDashboard: openDashboard)
            case .power:      PowerDetailPane(status: poller.latest, back: goBack)
            case .processes:  ProcessesDetailPane(status: poller.latest, back: goBack,
                                                  openDashboard: openDashboard)
            }
        }
        .frame(width: 288)
        .padding(.vertical, 6)
    }

    private func goBack() { pane = .root }

    private func openDashboard() { onOpenDashboard() }

    // MARK: - Root

    @ViewBuilder
    private var rootPane: some View {
        if let error = poller.lastError, poller.latest == nil {
            errorState(error)
        } else if let status = poller.latest {
            MenuRow(icon: "heart.fill",
                    label: "Health",
                    value: "\(status.healthScore.map(String.init) ?? "—") · \(status.healthScoreMsg ?? "—")",
                    tint: Severity.forHealth(status.healthScore))

            MenuRow(icon: "cpu", label: "CPU",
                    value: Fmt.percent(status.cpu?.usage, decimals: 1),
                    action: { pane = .cpu })

            if let gpu = status.measuredGPU, gpu.utilization != nil {
                MenuRow(icon: "cpu.fill", label: "GPU",
                        value: Fmt.percent(gpu.utilization, decimals: 1),
                        action: { pane = .gpu })
            }

            MenuRow(icon: "memorychip", label: "Memory",
                    value: Fmt.percent(status.memory?.usedPercent, decimals: 1),
                    action: { pane = .memory })

            MenuRow(icon: "internaldrive", label: "Disk",
                    value: "\(Fmt.percent(status.primaryDisk?.usedPercent)) used",
                    action: { pane = .storage })

            MenuRow(icon: "bolt.fill", label: "Power draw",
                    value: Fmt.watts(status.thermal?.systemPower),
                    action: { pane = .power })

            if let battery = status.battery {
                MenuRow(icon: batteryIcon(battery),
                        label: "Battery",
                        value: "\(battery.percent.map { "\($0)%" } ?? "—") · \(battery.status ?? "—")",
                        action: { pane = .power })
            }

            MenuRow(icon: "list.bullet",
                    label: "Top process",
                    value: status.topProcess?.name ?? "—",
                    action: { pane = .processes })

            Divider().padding(.vertical, 5)
            footer(status: status)
        } else {
            HStack {
                ProgressView().controlSize(.small)
                Text("Reading system status…")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider().padding(.vertical, 5)
            footer(status: nil)
        }
    }

    private func batteryIcon(_ battery: SystemStatus.Battery) -> String {
        guard let percent = battery.percent else { return "battery.50" }
        if battery.status == "AC" { return "battery.100.bolt" }
        switch percent {
        case ..<15:  return "battery.0"
        case ..<40:  return "battery.25"
        case ..<70:  return "battery.50"
        case ..<90:  return "battery.75"
        default:     return "battery.100"
        }
    }

    @ViewBuilder
    private func errorState(_ error: MoleError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Can't read system status", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if error == .notInstalled {
                Button("Install Mole…") {
                    MoleCLI.installMole()
                }
                .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)

        Divider().padding(.vertical, 5)
        footer(status: nil)
    }

    @ViewBuilder
    private func footer(status: SystemStatus?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuActionRow(icon: "square.grid.2x2", label: "Open Dashboard…", action: openDashboard)
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
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.primary.opacity(0.07) : .clear)
                    .padding(.horizontal, 7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
