import Foundation

/// Turns raw SMC keys into temperatures with names attached.
///
/// The key prefixes are Apple's, and stable across Apple silicon: `Tp` is a
/// performance core, `Te` an efficiency core, `Tg` a GPU cluster, and so on.
/// The *suffixes* differ per chip, which is why the sensor list is discovered
/// once at runtime rather than written down.
final class ThermalMonitor {

    /// Group prefixes Vitality is willing to put a name to. Anything else is
    /// still reported, but labelled as unidentified rather than guessed at.
    private enum Group: String, CaseIterable {
        case performanceCore = "Tp"
        case efficiencyCore = "Te"
        case gpu = "Tg"
        case battery = "TB"
        case storage = "TH"
        case enclosure = "Ts"

        var label: String {
            switch self {
            case .performanceCore: return "CPU performance core"
            case .efficiencyCore:  return "CPU efficiency core"
            case .gpu:             return "GPU"
            case .battery:         return "Battery"
            case .storage:         return "Storage"
            case .enclosure:       return "Enclosure"
            }
        }
    }

    private let smc: SMC?
    private var sensors: [SMC.Sensor]?

    init() { smc = SMC() }

    /// `nil` when this Mac exposes no usable sensors, so the UI can leave the
    /// section out entirely instead of showing a column of dashes.
    func sample() -> SystemStatus.Thermal? {
        guard let smc else { return nil }

        // Discovery walks ~2,200 keys, so it happens once and is kept. This
        // runs on the metrics queue, never on the main thread.
        if sensors == nil {
            sensors = smc.discoverSensors(matching: ["T"])
        }
        guard let sensors, !sensors.isEmpty else { return nil }

        var readings: [SystemStatus.Thermal.Sensor] = []
        var byGroup: [Group: [Double]] = [:]

        for sensor in sensors {
            guard let celsius = smc.read(sensor), Self.isPlausible(celsius) else { continue }
            let group = Group.allCases.first { sensor.name.hasPrefix($0.rawValue) }
            if let group { byGroup[group, default: []].append(celsius) }
            readings.append(.init(key: sensor.name,
                                  label: group?.label ?? "Unidentified sensor",
                                  celsius: celsius,
                                  isIdentified: group != nil))
        }

        guard !readings.isEmpty else { return nil }

        let cores = (byGroup[.performanceCore] ?? []) + (byGroup[.efficiencyCore] ?? [])

        // The hottest reading is taken from named sensors only. Several of the
        // unidentified ones idle above 70°C, and one of those permanently
        // winning "hottest" would be alarming and meaningless at once.
        let hottest = readings.filter(\.isIdentified).max { $0.celsius < $1.celsius }

        return SystemStatus.Thermal(
            cpu: Self.mean(cores),
            performanceCores: Self.mean(byGroup[.performanceCore]),
            efficiencyCores: Self.mean(byGroup[.efficiencyCore]),
            gpu: Self.mean(byGroup[.gpu]),
            battery: Self.mean(byGroup[.battery]),
            storage: Self.mean(byGroup[.storage]),
            enclosure: Self.mean(byGroup[.enclosure]),
            hottest: hottest,
            sensors: readings.sorted { $0.key < $1.key }
        )
    }

    /// Total system draw and what the adapter is putting in, both straight from
    /// the SMC's own rails.
    func power() -> (system: Double?, input: Double?) {
        guard let smc else { return (nil, nil) }
        return (positive(smc.value(forKey: "PSTR")), positive(smc.value(forKey: "PDTR")))
    }

    private func positive(_ value: Double?) -> Double? {
        guard let value, value > 0, value.isFinite else { return nil }
        return value
    }

    /// A sensor that is disconnected or unpowered reports 0 or a large negative
    /// number. Neither is a temperature.
    private static func isPlausible(_ celsius: Double) -> Bool {
        celsius > 1 && celsius < 150
    }

    /// The average across a cluster, not the maximum.
    ///
    /// Each core reports several sensors at different points on the die, and
    /// the hottest of them runs ~10°C above the rest even at idle. Averaging
    /// gives the figure that matches what other tools report; the peak is still
    /// available separately as `hottest`.
    private static func mean(_ values: [Double]?) -> Double? {
        guard let values, !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
