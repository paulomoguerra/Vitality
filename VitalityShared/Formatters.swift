import Foundation

enum Fmt {
    /// Human byte sizes. `.file` counting matches what Finder reports, so the
    /// numbers Vitality shows line up with what the user sees in Finder rather
    /// than disagreeing by ~7% the way binary (GiB) counting would.
    static func bytes(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f.string(fromByteCount: value)
    }

    static func percent(_ value: Double?, decimals: Int = 0) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(decimals)f%%", value)
    }

    static func watts(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        return String(format: "%.1f W", value)
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
