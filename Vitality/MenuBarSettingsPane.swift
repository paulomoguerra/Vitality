import SwiftUI

/// Chooses what rides in the menu bar, and how it looks.
///
/// Lives in the popover rather than a Settings window: the thing being
/// configured is two inches above the pane, and every change lands there live
/// as it is made. A separate window would put the preference further from the
/// result it changes.
struct MenuBarSettingsPane: View {
    @ObservedObject var settings: MenuBarSettings
    @ObservedObject var history: MenuBarHistory
    let status: SystemStatus?
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Menu bar", back: back)

            preview

            sectionLabel("Show")
            ForEach(MenuBarMetric.allCases) { metric in
                MetricToggleRow(metric: metric,
                                reading: metric.reading(from: status),
                                isOn: settings.binding(for: metric))
            }

            Divider().padding(.vertical, 8)

            sectionLabel("Appearance")

            settingRow("Colour") {
                Picker("", selection: $settings.colorMode) {
                    ForEach(MenuBarColorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            toggleRow("Labels", isOn: $settings.showsLabels)
            toggleRow("Graph", isOn: $settings.showsGraph)
            toggleRow("Vitality icon", isOn: $settings.showsAppIcon)

            if settings.showsGraph {
                Text("Last 40 seconds. Disk, battery and health move too slowly to plot.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }

            if settings.metrics.isEmpty {
                Text("Nothing selected — the icon stays so you can still open Vitality.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }

            Divider().padding(.vertical, 8)

            sectionLabel("Startup")
            toggleRow("Launch at login", isOn: $settings.launchAtLogin)
        }
        .padding(.bottom, 6)
    }

    /// The real strip, on a stand-in for the menu bar's own background.
    ///
    /// Turning on graphs — or selecting everything — makes a strip wider than
    /// the 288pt popover, so the tail fades out rather than being chopped off.
    /// The fade sits over empty background whenever it does fit, so it costs
    /// nothing in the common case.
    ///
    /// The strip has to be an *overlay* on an empty box, not a child in the
    /// layout. `.fixedSize()` means it reports its full ideal width upwards,
    /// and the popover then centres its whole 288pt column on that oversized
    /// row — every label in the pane slides left and clips. Overlay content
    /// never feeds its size back to the parent, which is exactly what's needed:
    /// draw at natural size, occupy only the width available.
    private var preview: some View {
        Color.clear
            .frame(height: 22)
            .overlay(alignment: .leading) {
                MenuBarStrip(status: status, settings: settings,
                             samples: history.samples(for:))
                    .fixedSize()
            }
            .mask(
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.94),
                                       .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            )
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.07))
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 3)
    }

    private func settingRow<Content: View>(_ label: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            content()
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }
}

/// One selectable metric, showing its live reading so the choice is made
/// against the actual number rather than a name.
private struct MetricToggleRow: View {
    let metric: MenuBarMetric
    let reading: MenuBarMetric.Reading
    @Binding var isOn: Bool

    @State private var hovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 0) {
                // The checkmark already carries the accent colour; tinting the
                // icon too turns the list into a wall of blue.
                Image(systemName: metric.icon)
                    .foregroundStyle(isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    // Wider than the popover's other rows: `battery.100` is the
                    // broadest symbol here and butts into its own label at 20.
                    .frame(width: 22)
                Text(metric.label).font(.system(size: 12))
                Spacer(minLength: 8)
                Text(reading.text)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(isOn ? 1 : 0)
                    .frame(width: 18)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
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
