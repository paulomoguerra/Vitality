import Darwin
import Foundation

/// Network throughput, read from the kernel's per-interface byte counters.
///
/// An instance rather than a namespace because throughput is a delta: `if_data`
/// reports bytes accumulated since the interface came up, so one reading says
/// nothing about the rate right now. The previous counters and the instant they
/// were taken have to survive between polls.
final class NetworkMonitor {

    private struct Counters {
        let input: UInt32
        let output: UInt32
    }

    private var previous: [String: Counters] = [:]
    private var lastSampledAt: Date?
    private var sessionDownBytes: Int64 = 0
    private var sessionUpBytes: Int64 = 0

    func sample() -> SystemStatus.Network? {
        guard let current = readCounters() else { return nil }
        let now = Date()

        defer {
            self.previous = current
            self.lastSampledAt = now
        }

        guard let lastSampledAt else {
            // First poll after launch: the counters are real, but there is
            // nothing to subtract them from. A rate of zero would draw a lull
            // that never happened, so the rate is simply unknown.
            return SystemStatus.Network(downBytesPerSec: nil,
                                        upBytesPerSec: nil,
                                        sessionDownBytes: sessionDownBytes,
                                        sessionUpBytes: sessionUpBytes,
                                        interface: nil)
        }

        var downDelta: Int64 = 0
        var upDelta: Int64 = 0
        var busiest: (name: String, bytes: Int64)?

        // Sorted so an idle machine, where every delta is zero, keeps naming the
        // same interface instead of flipping with the dictionary's order.
        for (name, counters) in current.sorted(by: { $0.key < $1.key }) {
            // An interface seen for the first time — a cable just plugged in —
            // has no predecessor, and its lifetime total is not this poll's
            // traffic.
            guard let before = previous[name] else { continue }

            // The counters are 32-bit and wrap: at 10 Gbit/s that happens every
            // few seconds. Wrapping subtraction *before* widening gives the true
            // delta; subtracting as Int64 would give a ~4 GB negative spike.
            let down = Int64(counters.input &- before.input)
            let up = Int64(counters.output &- before.output)
            downDelta += down
            upDelta += up

            let combined = down + up
            if combined > (busiest?.bytes ?? -1) { busiest = (name, combined) }
        }

        sessionDownBytes += downDelta
        sessionUpBytes += upDelta

        // Two polls inside the same instant would divide by ~zero and print a
        // spike that is an artefact of the clock. Keep the totals, drop the rate.
        let elapsed = now.timeIntervalSince(lastSampledAt)
        let hasRate = elapsed > 0

        return SystemStatus.Network(
            downBytesPerSec: hasRate ? Double(downDelta) / elapsed : nil,
            upBytesPerSec: hasRate ? Double(upDelta) / elapsed : nil,
            sessionDownBytes: sessionDownBytes,
            sessionUpBytes: sessionUpBytes,
            interface: busiest?.name
        )
    }

    /// Per-interface counters for the links a person would call "my network".
    ///
    /// `AF_LINK` is the datalink entry, the only one carrying `if_data`; the
    /// `AF_INET`/`AF_INET6` entries for the same interface carry addresses and
    /// would otherwise be counted as duplicates.
    private func readCounters() -> [String: Counters]? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return nil }
        defer { freeifaddrs(head) }

        var counters: [String: Counters] = [:]
        for entry in sequence(first: head, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  let name = interface.ifa_name.map({ String(cString: $0) }),
                  Self.isPhysical(name),
                  let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self)
            else { continue }

            counters[name] = Counters(input: data.pointee.ifi_ibytes,
                                      output: data.pointee.ifi_obytes)
        }
        return counters
    }

    /// `en*` is the whole filter, and it is the right one: Wi-Fi, Ethernet and
    /// Thunderbolt/USB adapters are named that way, while everything that would
    /// double-count or invent traffic is not. AirDrop's `awdl`/`llw` links, VPN
    /// `utun` tunnels, internet-sharing `bridge`s and the internal `anpi`
    /// management link all ride out over a physical NIC that is already counted,
    /// and `lo` loopback traffic never touches the network at all.
    private static func isPhysical(_ name: String) -> Bool {
        name.hasPrefix("en")
    }
}
