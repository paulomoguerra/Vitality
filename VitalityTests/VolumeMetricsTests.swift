import XCTest

/// `disk(path:…)` is the only conversion from volume figures to a dashboard
/// disk. Missing free space must be omitted, not invented as 0 (which looks
/// 100% full and fires a disk-full alert).
final class VolumeMetricsTests: XCTestCase {

    private func disk(path: String = "/",
                      name: String? = "Macintosh HD",
                      total: Int? = 1_000_000,
                      available: Int64? = nil,
                      importantUsage: Int64? = nil,
                      isInternal: Bool? = nil,
                      isRemovable: Bool? = nil) -> SystemStatus.Disk? {
        VolumeMetricsProvider.disk(
            path: path, name: name, total: total,
            available: available, importantUsage: importantUsage,
            isInternal: isInternal, isRemovable: isRemovable
        )
    }

    func testOmitsVolumeWhenAvailableCapacityIsMissing() {
        XCTAssertNil(disk(available: nil, importantUsage: nil))
    }

    func testOmitsVolumeWhenTotalCapacityIsMissing() {
        XCTAssertNil(disk(total: nil, available: 100_000))
    }

    func testPrefersImportantUsageOverRawAvailable() {
        let volume = disk(available: 10_000, importantUsage: 200_000)

        XCTAssertEqual(volume?.used, 800_000)
        XCTAssertEqual(volume?.total, 1_000_000)
        XCTAssertEqual(volume?.usedPercent, 80)
        XCTAssertEqual(volume?.free, 200_000)
    }

    func testFallsBackToRawAvailableWhenImportantUsageIsMissing() {
        let volume = disk(available: 250_000)

        XCTAssertEqual(volume?.used, 750_000)
        XCTAssertEqual(volume?.free, 250_000)
    }

    func testDoesNotInventInternalOrRemovableFlags() {
        let volume = disk(available: 500_000)

        XCTAssertNil(volume?.isInternal)
        XCTAssertNil(volume?.isRemovable)
    }

    func testDropsSimulatorRuntimeVolumes() {
        XCTAssertNil(disk(
            path: "/Users/me/Library/Developer/CoreSimulator/Volumes/iOS",
            available: 500_000
        ))
    }
}
