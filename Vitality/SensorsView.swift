import SwiftUI

/// Every temperature sensor this Mac reports, grouped by what it measures.
///
/// The popover shows the six cluster averages, which is what anyone actually
/// wants. This is the other half of the answer: the individual readings those
/// averages come from, plus the ones Vitality can read but cannot name. A tool
/// that hides the sensors it doesn't understand is asking to be trusted rather
/// than checked.
struct SensorsView: View {
    @ObservedObject var poller: StatusPoller
    @State private var showRawSensors = false

    var body: some View {
        if poller.latest == nil {
            ProgressView("Reading sensors…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(13)
                .background(ThemeCardBackground())
        } else if let thermal = poller.latest?.thermal {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let hottest = thermal.hottest {
                        hottestSensor(hottest)
                    }
                    summary(thermal)

                    ForEach(groups(thermal), id: \.name) { group in
                        SensorGroupView(name: group.name, sensors: group.sensors)
                    }

                    let unidentified = thermal.sensors.filter { !$0.isIdentified }
                    if !unidentified.isEmpty {
                        DisclosureGroup(isExpanded: $showRawSensors) {
                            SensorGroupView(name: "Raw readings", sensors: unidentified)
                                .padding(.top, 4)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform.path.ecg")
                                    .accessibilityHidden(true)
                                Text("Raw sensors")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("\(unidentified.count)")
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(Theme.inkTertiary)
                            }
                            .foregroundStyle(Theme.inkSecondary)
                        }
                        .accessibilityHint("These readings are real but Vitality cannot identify their component")
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(13)
            .background(ThemeCardBackground())
        } else {
            VStack(spacing: 6) {
                Image(systemName: "thermometer.medium.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.inkTertiary)
                Text("No temperature sensors")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text("macOS did not return any temperature readings for this Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(13)
            .background(ThemeCardBackground())
        }
    }

    private func hottestSensor(_ sensor: SystemStatus.Thermal.Sensor) -> some View {
        let severity = Severity.level(forTemperature: sensor.celsius)
        return HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .foregroundStyle(severity?.color ?? Theme.statusWarn)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hottest sensor")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Text(sensor.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(sensor.key)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.inkTertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.celsius(sensor.celsius, decimals: 1))
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(severity?.color ?? Theme.ink)
                Text(severityLabel(severity))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(severity?.color ?? Theme.inkSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(ThemeCardBackground(radius: Theme.nestedRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hottest sensor, \(sensor.label), \(Fmt.celsius(sensor.celsius, decimals: 1)), \(severityLabel(severity))")
    }

    private func severityLabel(_ severity: Severity.Level?) -> String {
        switch severity {
        case .normal: return "Normal"
        case .warning: return "Warm"
        case .critical: return "Critical"
        case nil: return "Status unavailable"
        }
    }

    private func summary(_ thermal: SystemStatus.Thermal) -> some View {
        let tiles: [(String, Double?)] = [
            ("CPU", thermal.cpu), ("GPU", thermal.gpu), ("Battery", thermal.battery),
            ("Storage", thermal.storage), ("Enclosure", thermal.enclosure),
        ].filter { $0.1 != nil }

        return VStack(alignment: .leading, spacing: 6) {
            Text("Averages")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)

            HStack(spacing: 8) {
                ForEach(tiles, id: \.0) { label, value in
                    VStack(spacing: 2) {
                        Text(Fmt.celsius(value, decimals: 1))
                            .font(.system(size: 15, weight: .medium).monospacedDigit())
                            .foregroundStyle(Severity.level(forTemperature: value)?.color ?? Theme.ink)
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(ThemeCardBackground(radius: Theme.nestedRadius))
                }
            }
        }
    }

    /// Named groups in a fixed order. Unidentified readings are deliberately
    /// kept out of this primary list and exposed through the collapsed Raw
    /// sensors disclosure below.
    private func groups(_ thermal: SystemStatus.Thermal)
    -> [(name: String, sensors: [SystemStatus.Thermal.Sensor])] {
        let order = ["CPU performance core", "CPU efficiency core", "GPU",
                     "Battery", "Storage", "Enclosure"]
        let byLabel = Dictionary(grouping: thermal.sensors.filter { $0.isIdentified }, by: \.label)

        return order.compactMap { label -> (String, [SystemStatus.Thermal.Sensor])? in
            guard let sensors = byLabel[label], !sensors.isEmpty else { return nil }
            return (label, sensors.sorted { $0.celsius > $1.celsius })
        }
    }
}

private struct SensorGroupView: View {
    let name: String
    let sensors: [SystemStatus.Thermal.Sensor]

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(sensors.count)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Theme.inkTertiary)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(sensors.sorted { $0.celsius > $1.celsius }) { sensor in
                    HStack(spacing: 6) {
                        Text(sensor.key)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.inkTertiary)
                        Spacer(minLength: 4)
                        Text(Fmt.celsius(sensor.celsius, decimals: 1))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(Severity.level(forTemperature: sensor.celsius)?.color
                                             ?? Theme.ink)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(ThemeCardBackground(radius: 8))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(name), \(sensor.key), \(Fmt.celsius(sensor.celsius, decimals: 1))")
                }
            }
        }
    }
}
