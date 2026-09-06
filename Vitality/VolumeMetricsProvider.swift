import Foundation

/// Reads mounted volumes and converts their resource values to dashboard disks.
struct VolumeMetricsProvider {

    private let resourceKeys: [URLResourceKey] = [
        .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsBrowsableKey,
    ]

    func sample() -> [SystemStatus.Disk] {
        guard let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: resourceKeys, options: [.skipHiddenVolumes]
        ) else { return [] }

        return volumes.compactMap { url -> SystemStatus.Disk? in
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else {
                return nil
            }
            return Self.disk(for: url, values: values)
        }
        .sorted { ($0.mount == "/" ? 0 : 1) < ($1.mount == "/" ? 0 : 1) }
    }

    /// Kept as a pure conversion boundary so volume filtering and arithmetic
    /// can be tested without mounting or unmounting anything.
    static func disk(for url: URL, values: URLResourceValues) -> SystemStatus.Disk? {
        disk(
            path: url.path,
            name: values.volumeName,
            total: values.volumeTotalCapacity,
            available: values.volumeAvailableCapacity.map(Int64.init),
            importantUsage: values.volumeAvailableCapacityForImportantUsage,
            isInternal: values.volumeIsInternal,
            isRemovable: values.volumeIsRemovable
        )
    }

    static func disk(path: String,
                     name: String?,
                     total: Int?,
                     available: Int64?,
                     importantUsage: Int64?,
                     isInternal: Bool?,
                     isRemovable: Bool?) -> SystemStatus.Disk? {
        guard let total, total > 0 else { return nil }

        // Xcode's simulator runtimes mount as browsable volumes and are
        // permanently near-full. They're Xcode's business, not the user's.
        if path.contains("/CoreSimulator/Volumes/") { return nil }

        // Prefer Finder's "available" figure so a volume with purgeable space
        // is not treated as critically full. Missing both keys is unknown, not
        // zero — inventing 0 free fires a disk-full alert.
        let free: Int64
        if let importantUsage {
            free = importantUsage
        } else if let available {
            free = available
        } else {
            return nil
        }

        let capacity = Int64(total)
        let used = max(0, capacity - free)

        return SystemStatus.Disk(
            mount: path,
            name: name,
            used: used,
            total: capacity,
            usedPercent: Double(used) / Double(capacity) * 100,
            isInternal: isInternal,
            isRemovable: isRemovable
        )
    }
}
