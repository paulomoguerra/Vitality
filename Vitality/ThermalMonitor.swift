import Foundation

/// Turns raw SMC keys into temperatures with names attached.
///
/// The key prefixes are Apple's, and stable across Apple silicon: `Tp` is a
/// performance core, `Te` an efficiency core, `Tg` a GPU cluster, and so on.
/// The *suffixes* differ per chip, which is why the sensor list is discovered
/// once at runtime rather than written down.
///
/// Reading a sensor is a kernel round trip, and this Mac exposes 200 of them.
/// Reading all 200 every second cost 46ms — measurably the most expensive thing
/// Vitality did. So the sweep is split by how fast the thing being measured can
/// actually change: silicon every poll, everything else every few seconds.
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

        /// Whether this group can meaningfully change between two polls a
        /// second apart.
        ///
        /// A die goes from idle to throttling in well under a second, so those
        /// sensors are read every time. A slab of aluminium, a battery and an
        /// SSD have thermal mass measured in minutes — sampling them at 1 Hz
        /// reports the same number five times over and calls it live.
        var changesQuickly: Bool {
            switch self {
            case .performanceCore, .efficiencyCore, .gpu: return true
            case .battery, .storage, .enclosure:          return false
            }
        }
    }

    /// A discovered sensor with its group resolved once, rather than matched
    /// against every prefix on every read.
    private struct Probe {
        let sensor: SMC.Sensor
        let group: Group?
        let label: String
    }

    /// How many polls pass between sweeps of the slow sensors. At the poller's
    /// 1 Hz that is five seconds.
    private static let slowSweepInterval = 5

    private let smc: SMC?

    /// Read every poll: the silicon.
    private var fast: [Probe] = []
    /// Read every `slowSweepInterval` polls: chassis, battery, storage, and
    /// every sensor Vitality cannot name — the last of which appear only in the
    /// Sensors tab.
    private var slow: [Probe] = []
    private var didDiscover = false

    /// The last slow sweep, reused in between so no row disappears from the
    /// Sensors tab and no average blanks out just because this poll skipped it.
    private var slowReadings: [SystemStatus.Thermal.Sensor] = []
    private var slowClusters: [Group: [Double]] = [:]
    private var slowHottest: SystemStatus.Thermal.Sensor?

    /// Starts at the interval so the first poll sweeps rather than showing an
    /// empty Sensors tab for five seconds.
    private var pollsSinceSweep = ThermalMonitor.slowSweepInterval

    init() { smc = SMC() }

    /// `nil` when this Mac exposes no usable sensors, so the UI can leave the
    /// section out entirely instead of showing a column of dashes.
    func sample() -> SystemStatus.Thermal? {
        guard let smc else { return nil }

        // Discovery walks ~2,200 keys, so it happens once and is kept. This
        // runs on the metrics queue, never on the main thread.
        if !didDiscover {
            discover(using: smc)
            didDiscover = true
        }
        guard !fast.isEmpty || !slow.isEmpty else { return nil }

        // A sensor whose read returns nil is unsupported rather than idle — the
        // driver has no answer for it and never will. Reading it again every
        // second is a kernel round trip that can only fail, so drop it for good.
        var deadKeys: Set<UInt32> = []

        let (readings, means, hottestFast) = read(fast, using: smc, into: &deadKeys)

        if pollsSinceSweep >= Self.slowSweepInterval {
            pollsSinceSweep = 1
            (slowReadings, slowClusters, slowHottest) = read(slow, using: smc, into: &deadKeys)
        } else {
            pollsSinceSweep += 1
        }

        if !deadKeys.isEmpty {
            fast.removeAll { deadKeys.contains($0.sensor.key) }
            slow.removeAll { deadKeys.contains($0.sensor.key) }
        }

        // Both lists were sorted by key at discovery and no group spans the two,
        // so concatenating keeps every group's own rows in key order without
        // re-sorting 168 strings once a second.
        let all = readings + slowReadings
        guard !all.isEmpty else { return nil }

        // The hottest reading is taken from named sensors only. Several of the
        // unidentified ones idle above 70°C, and one of those permanently
        // winning "hottest" would be alarming and meaningless at once.
        let hottest = [hottestFast, slowHottest]
            .compactMap { $0 }
            .filter(\.isIdentified)
            .max { $0.celsius < $1.celsius }

        let cores = (means[.performanceCore] ?? []) + (means[.efficiencyCore] ?? [])

        return SystemStatus.Thermal(
            cpu: Self.mean(cores),
            performanceCores: Self.mean(means[.performanceCore]),
            efficiencyCores: Self.mean(means[.efficiencyCore]),
            gpu: Self.mean(means[.gpu]),
            battery: Self.mean(slowClusters[.battery]),
            storage: Self.mean(slowClusters[.storage]),
            enclosure: Self.mean(slowClusters[.enclosure]),
            hottest: hottest,
            sensors: all
        )
    }

    /// Reads a tier and returns its readings, its per-group cluster values, and
    /// the hottest sensor it saw. Keys that the driver refuses outright are
    /// collected in `dead` for the caller to retire.
    private func read(_ probes: [Probe],
                      using smc: SMC,
                      into dead: inout Set<UInt32>)
    -> ([SystemStatus.Thermal.Sensor], [Group: [Double]], SystemStatus.Thermal.Sensor?) {
        var readings: [SystemStatus.Thermal.Sensor] = []
        readings.reserveCapacity(probes.count)
        var byGroup: [Group: [Double]] = [:]
        var hottest: SystemStatus.Thermal.Sensor?

        for probe in probes {
            guard let celsius = smc.read(probe.sensor) else {
                dead.insert(probe.sensor.key)
                continue
            }
            guard Self.isPlausible(celsius) else { continue }

            if let group = probe.group { byGroup[group, default: []].append(celsius) }
            let reading = SystemStatus.Thermal.Sensor(key: probe.sensor.name,
                                                      label: probe.label,
                                                      celsius: celsius,
                                                      isIdentified: probe.group != nil)
            readings.append(reading)
            // Tracked in the same pass rather than by a second scan over the
            // results.
            if reading.isIdentified, celsius > (hottest?.celsius ?? -Double.infinity) {
                hottest = reading
            }
        }
        return (readings, byGroup, hottest)
    }

    /// Total system draw and what the adapter is putting in, both straight from
    /// the SMC's own rails.
    func power() -> (system: Double?, input: Double?) {
        guard let smc else { return (nil, nil) }
        return (positive(smc.value(forKey: "PSTR")), positive(smc.value(forKey: "PDTR")))
    }

    private func discover(using smc: SMC) {
        let probes = smc.discoverSensors(matching: ["T"])
            .sorted { $0.name < $1.name }
            .map { sensor -> Probe in
                let group = Group.allCases.first { sensor.name.hasPrefix($0.rawValue) }
                return Probe(sensor: sensor,
                             group: group,
                             label: group?.label ?? "Unidentified sensor")
            }
        // An unnamed sensor is slow by default: it is only ever shown as a row
        // in the Sensors tab, so there is nothing for a faster read to feed.
        fast = probes.filter { $0.group?.changesQuickly == true }
        slow = probes.filter { $0.group?.changesQuickly != true }
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
