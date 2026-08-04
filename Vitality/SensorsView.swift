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

    var body: some View {
        if let thermal = poller.latest?.thermal {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary(thermal)

                    ForEach(groups(thermal), id: \.name) { group in
                        SensorGroupView(name: group.name, sensors: group.sensors)
                    }
                }
                .padding(.vertical, 4)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "thermometer.medium.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("No temperature sensors")
                    .font(.system(size: 13, weight: .medium))
                Text("Vitality reads these from the SMC, which this Mac isn't answering.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func summary(_ thermal: SystemStatus.Thermal) -> some View {
        let tiles: [(String, Double?)] = [
            ("CPU", thermal.cpu), ("GPU", thermal.gpu), ("Battery", thermal.battery),
            ("Storage", thermal.storage), ("Enclosure", thermal.enclosure),
        ]

        return VStack(alignment: .leading, spacing: 6) {
            Text("Averages")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(tiles, id: \.0) { label, value in
                    VStack(spacing: 2) {
                        Text(Fmt.celsius(value, decimals: 1))
                            .font(.system(size: 15, weight: .medium).monospacedDigit())
                            .foregroundStyle(Severity.level(forTemperature: value)?.color ?? .primary)
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                }
            }
        }
    }

    /// Named groups in a fixed order, with the unidentified sensors last —
    /// present, but never competing for attention with the ones that mean
    /// something.
    private func groups(_ thermal: SystemStatus.Thermal)
    -> [(name: String, sensors: [SystemStatus.Thermal.Sensor])] {
        let order = ["CPU performance core", "CPU efficiency core", "GPU",
                     "Battery", "Storage", "Enclosure"]
        let byLabel = Dictionary(grouping: thermal.sensors, by: \.label)

        var result = order.compactMap { label -> (String, [SystemStatus.Thermal.Sensor])? in
            guard let sensors = byLabel[label], !sensors.isEmpty else { return nil }
            return (label, sensors)
        }
        if let unknown = byLabel["Unidentified sensor"], !unknown.isEmpty {
            result.append(("Unidentified — read correctly, purpose unknown", unknown))
        }
        return result
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
                Text("\(sensors.count)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(sensors) { sensor in
                    HStack(spacing: 6) {
                        Text(sensor.key)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 4)
                        Text(Fmt.celsius(sensor.celsius, decimals: 1))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(Severity.level(forTemperature: sensor.celsius)?.color
                                             ?? .primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                }
            }
        }
    }
}
