import AppKit
import SwiftUI

/// Legacy compact configuration pane kept for the popover's detail route.
/// The canonical configuration now lives in the native Settings scene below.
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

            settingRow("Color") {
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
            toggleRow("Launch Vitality at login", isOn: $settings.launchAtLogin)
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

// MARK: - Native Settings

/// Root for the macOS Settings scene. Keeping this as a real Settings scene
/// gives users the expected Command-comma entry point and a stable place for
/// preferences that do not belong in the compact menu bar popover.
struct SettingsRootView: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        TabView {
            Group {
                if let poller = appDelegate.statusPollerForUI,
                   let history = appDelegate.menuBarHistoryForUI {
                    SettingsMenuBarTab(settings: appDelegate.settingsForUI,
                                       poller: poller, history: history)
                } else {
                    SettingsUnavailableTab(title: "Menu bar", message: "Start Vitality to edit menu bar preferences.")
                }
            }
            .tabItem { Label("Menu bar", systemImage: "menubar.rectangle") }

            Group {
                if let alerts = appDelegate.alertCenterForUI {
                    AlertsPreferencesView(alerts: alerts)
                } else {
                    SettingsUnavailableTab(title: "Alerts", message: "Alerts become available when Vitality starts monitoring this Mac.")
                }
            }
            .tabItem { Label("Alerts", systemImage: "bell") }

            GeneralPreferencesView(settings: appDelegate.settingsForUI)
                .tabItem { Label("General", systemImage: "gearshape") }

            AboutPreferencesView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(minWidth: 620, minHeight: 450)
        .preferredColorScheme(.dark)
    }
}

private struct SettingsUnavailableTab: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title2.weight(.semibold))
            Text(message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsMenuBarTab: View {
    @ObservedObject var settings: MenuBarSettings
    @ObservedObject var poller: StatusPoller
    @ObservedObject var history: MenuBarHistory

    var body: some View {
        MenuBarPreferencesView(settings: settings, history: history, status: poller.latest)
    }
}

private struct MenuBarPreferencesView: View {
    @ObservedObject var settings: MenuBarSettings
    @ObservedObject var history: MenuBarHistory
    let status: SystemStatus?

    var body: some View {
        Form {
            Section {
                menuBarPreview
                Text("The preview updates as you change these choices.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Menu bar metrics")
            }

            Section {
                ForEach(MenuBarMetric.allCases) { metric in
                    HStack(spacing: 12) {
                        Label(metric.label, systemImage: metric.icon)
                        Spacer()
                        Text(metric.reading(from: status).text)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Toggle("Show \(metric.label)", isOn: settings.binding(for: metric))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel("Show \(metric.label)")
                    }
                    .frame(minHeight: 32)
                }
            } header: {
                Text("Show")
            }

            Section {
                Picker("Color", selection: $settings.colorMode) {
                    ForEach(MenuBarColorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Toggle("Show labels", isOn: $settings.showsLabels)
                Toggle("Show graph", isOn: $settings.showsGraph)
                Toggle("Show Vitality icon", isOn: $settings.showsAppIcon)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Graphs show the last 40 seconds for readings that change quickly.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var menuBarPreview: some View {
        MenuBarStrip(status: status, settings: settings, samples: history.samples(for:))
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(.horizontal, 10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.cardBorder))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Menu bar preview")
    }
}

private struct AlertsPreferencesView: View {
    @ObservedObject var alerts: AlertCenter

    var body: some View {
        Form {
            Section {
                Toggle("Send notifications", isOn: $alerts.notificationsEnabled)
                Text("Vitality keeps showing active alerts in the dashboard when notifications are off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Notifications")
            }

            Section {
                ForEach(AlertCenter.allRules) { rule in
                    HStack(alignment: .top, spacing: 12) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.title)
                                Text(rule.detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: rule.icon)
                                .frame(width: 18)
                        }
                        Spacer()
                        Toggle("Monitor \(rule.title)", isOn: alerts.binding(for: rule.id))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel("Monitor \(rule.title)")
                    }
                    .frame(minHeight: 38)
                }
            } header: {
                Text("Rules")
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct GeneralPreferencesView: View {
    @ObservedObject var settings: MenuBarSettings

    var body: some View {
        Form {
            Section {
                Toggle("Launch Vitality at login", isOn: $settings.launchAtLogin)
                Text("Vitality asks macOS to keep the monitor available after you sign in. It does not enable this on first launch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Startup")
            }

            Section {
                Label("Local monitoring", systemImage: "lock.shield")
                Text("Metrics stay on this Mac. Vitality does not require an account or send telemetry.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy")
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct AboutPreferencesView: View {
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "gauge.medium")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 52, height: 52)
                        .background(Theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vitality").font(.title2.weight(.semibold))
                        Text("A calm, local system monitor for Mac.")
                            .foregroundStyle(.secondary)
                        Text("Version 1.0")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }

                Divider()

                Text("Support Vitality")
                    .font(.headline)
                Text("Vitality is free and local. If it earned a place in your menu bar, a coffee over Lightning helps keep it maintained.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let qr = Support.qrImage {
                    Image(nsImage: qr)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 132, height: 132)
                        .padding(10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.12)))
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Text(Support.abbreviated)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    Button(copied ? "Copied address" : "Copy Lightning address") {
                        Support.copyToPasteboard()
                        copied = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    if let walletURL = Support.walletURL {
                        Button("Open wallet") { NSWorkspace.shared.open(walletURL) }
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
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
