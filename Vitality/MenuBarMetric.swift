import SwiftUI

/// One live figure that can ride in the menu bar beside the Vitality icon.
///
/// `allCases` is also the display order. Selection is a set rather than a
/// sequence on purpose: a user reordering chips by dragging is a fiddly
/// interaction that buys nothing, and a fixed order means the strip never
/// ends up in a layout nobody chose.
enum MenuBarMetric: String, CaseIterable, Identifiable, Codable {
    case cpu, cpuTemp, gpu, gpuTemp, memory, disk, power, powerIn, netDown, netUp, battery, health

    var id: String { rawValue }

    /// Full name, for the settings list.
    var label: String {
        switch self {
        case .cpu:      return "CPU"
        case .cpuTemp:  return "CPU temperature"
        case .gpu:      return "GPU"
        case .gpuTemp:  return "GPU temperature"
        case .memory:   return "Memory"
        case .disk:     return "Disk"
        case .power:    return "Power draw"
        case .powerIn:  return "Power in"
        case .netDown:  return "Network down"
        case .netUp:    return "Network up"
        case .battery:  return "Battery"
        case .health:   return "Health"
        }
    }

    /// The tag shown in the menu bar itself. Deliberately letters, not a glyph:
    /// at 9pt, `cpu` and `cpu.fill` are a coin toss, and a bare number with no
    /// tag at all is worse still. "CPU" is never ambiguous.
    ///
    /// The two arrows are the exception that proves it: a direction is what an
    /// arrow means at any size, and "DOWN"/"UP" beside a rate would be read as
    /// the link being down rather than as traffic inbound.
    var shortLabel: String {
        switch self {
        case .cpu:      return "CPU"
        case .cpuTemp:  return "CPU°"
        case .gpu:      return "GPU"
        case .gpuTemp:  return "GPU°"
        case .memory:   return "RAM"
        case .disk:     return "SSD"
        case .power:    return "PWR"
        case .powerIn:  return "IN"
        case .netDown:  return "↓"
        case .netUp:    return "↑"
        case .battery:  return "BAT"
        case .health:   return "HLTH"
        }
    }

    /// Matches the icon this metric uses in the popover, so the settings list
    /// reads as the same object the user already clicks on the root pane.
    var icon: String {
        switch self {
        case .cpu:      return "cpu"
        case .cpuTemp:  return "thermometer.medium"
        case .gpu:      return "cpu.fill"
        case .gpuTemp:  return "thermometer.medium"
        case .memory:   return "memorychip"
        case .disk:     return "internaldrive"
        case .power:    return "bolt.fill"
        case .powerIn:  return "powerplug.fill"
        case .netDown:  return "arrow.down.circle"
        case .netUp:    return "arrow.up.circle"
        case .battery:  return "battery.100"
        case .health:   return "heart.fill"
        }
    }

    /// The widest string this metric can ever produce. The chip reserves this
    /// much room so the whole menu bar doesn't shuffle sideways every time a
    /// reading crosses from 9% to 10%.
    var widestValue: String {
        switch self {
        case .power, .powerIn:   return "88.8 W"
        // Three digits, not two: gigabit Ethernet and Wi-Fi 6 sit above
        // 100 MB/s routinely, and one extra digit would shove the whole
        // menu bar sideways at exactly the moment the number is interesting.
        case .netDown, .netUp:   return "888.8 MB/s"
        case .health:            return "100"
        case .cpuTemp, .gpuTemp: return "100°"
        default:                 return "100%"
        }
    }

    /// Whether a 40-second graph says anything.
    ///
    /// Disk, battery and health move over hours, so their sparkline is a
    /// motionless brick that reads as a bar chart of nothing. Drawing a graph
    /// for them would be decoration pretending to be information.
    var isGraphable: Bool {
        switch self {
        case .cpu, .gpu, .memory, .power, .powerIn, .cpuTemp, .gpuTemp,
             .netDown, .netUp:          return true
        case .disk, .battery, .health:  return false
        }
    }

    struct Reading {
        /// How a sample maps onto the sparkline's vertical axis.
        enum Scale {
            /// 0–100 against a fixed ceiling, so a flat 20% CPU line stays low.
            case percent
            /// No natural ceiling (watts) — plotted against the window's own
            /// maximum, which makes it a shape-of-the-last-40-seconds graph.
            case relative
        }

        let text: String
        let sample: Double?
        let scale: Scale
        let level: Severity.Level?
    }

    func reading(from status: SystemStatus?) -> Reading {
        switch self {
        case .cpu:
            return usage(status?.cpu?.usage)
        case .gpu:
            return usage(status?.gpu?.utilization)
        case .memory:
            return usage(status?.memory?.usedPercent)
        case .disk:
            return usage(status?.primaryDisk?.usedPercent)

        case .battery:
            let percent = status?.battery?.percent.map(Double.init)
            return Reading(text: percent.map { Fmt.percent($0) } ?? "—",
                           sample: percent,
                           scale: .percent,
                           level: Severity.level(forCharge: percent))

        case .power:
            let watts = status?.headlinePower
            return Reading(text: Fmt.watts(watts), sample: watts, scale: .relative, level: nil)

        case .powerIn:
            let watts = status?.power?.inputWatts
            return Reading(text: Fmt.watts(watts), sample: watts, scale: .relative, level: nil)

        case .netDown:
            let rate = status?.network?.downBytesPerSec
            return Reading(text: Fmt.rate(rate), sample: rate, scale: .relative, level: nil)

        case .netUp:
            let rate = status?.network?.upBytesPerSec
            return Reading(text: Fmt.rate(rate), sample: rate, scale: .relative, level: nil)

        case .cpuTemp:
            return temperature(status?.thermal?.cpu)

        case .gpuTemp:
            return temperature(status?.thermal?.gpu)

        case .health:
            let score = status?.healthScore
            return Reading(text: score.map(String.init) ?? "—",
                           sample: score.map(Double.init),
                           scale: .percent,
                           level: Severity.level(forHealth: score))
        }
    }

    /// Temperature rides the `.percent` scale deliberately: it is not a
    /// percentage, but a fixed 0–100 ceiling is the right axis for a die that
    /// idles near 50°C and throttles above 100°C.
    private func temperature(_ value: Double?) -> Reading {
        Reading(text: Fmt.celsius(value),
                sample: value,
                scale: .percent,
                level: Severity.level(forTemperature: value))
    }

    private func usage(_ value: Double?) -> Reading {
        Reading(text: Fmt.percent(value),
                sample: value,
                scale: .percent,
                level: Severity.level(forUsage: value))
    }
}
