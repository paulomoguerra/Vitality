import Foundation

enum Fmt {
    /// One shared instance: formatters are expensive to create, and this one is
    /// asked for dozens of strings per render while the dashboard is open. Only
    /// ever touched from SwiftUI view bodies, so main-thread confinement holds.
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }()

    /// Human byte sizes. `.file` counting matches what Finder reports, so the
    /// numbers Vitality shows line up with what the user sees in Finder rather
    /// than disagreeing by ~7% the way binary (GiB) counting would.
    static func bytes(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        return byteFormatter.string(fromByteCount: value)
    }

    /// Throughput, on the same units as `bytes` so a rate and a total read as
    /// the same kind of number.
    ///
    /// Below a kilobyte a second the exact figure is noise — a chip flickering
    /// between "312 bytes/s" and "0 bytes/s" reads as broken rather than idle —
    /// so everything under that floor is shown as idle.
    static func rate(_ bytesPerSec: Double?) -> String {
        guard let bytesPerSec, bytesPerSec >= 1_000 else {
            return bytesPerSec == nil ? "—" : "0 KB/s"
        }
        // Clamped because converting a Double past Int64's range traps, and a
        // division by a near-zero interval must never be able to crash the app.
        return byteFormatter.string(fromByteCount: Int64(min(bytesPerSec, 1e15))) + "/s"
    }

    static func percent(_ value: Double?, decimals: Int = 0) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(decimals)f%%", value)
    }

    static func watts(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        return String(format: "%.1f W", value)
    }

    static func celsius(_ value: Double?, decimals: Int = 0) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(decimals)f°", value)
    }

    static func load(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value)
    }

    /// Load average is only meaningful relative to core count: 4.0 is idle on a
    /// 10-core machine and badly saturated on a dual-core one.
    static func loadRatio(_ load: Double?, cores: Int?) -> Double? {
        guard let load, let cores, cores > 0 else { return nil }
        return load / Double(cores) * 100
    }

    static func relativeTime(from date: Date?) -> String {
        guard let date else { return "—" }
        let elapsed = Int(Date().timeIntervalSince(date))
        if elapsed < 2 { return "just now" }
        if elapsed < 60 { return "\(elapsed)s ago" }
        if elapsed < 3600 { return "\(elapsed / 60)m ago" }
        return "\(elapsed / 3600)h ago"
    }
}
