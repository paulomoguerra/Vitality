import XCTest

/// The widget and the app can be different builds, so every field on a
/// snapshot stays optional. The helpers below are what the UI actually
/// asks — a name, a free-space figure, which disk is the boot volume —
/// and they have to stay well-defined when half the payload is missing.
final class SystemStatusTests: XCTestCase {

    private func disk(mount: String? = "/",
                      name: String? = "Macintosh HD",
                      used: Int64? = 60,
                      total: Int64? = 100) -> SystemStatus.Disk {
        SystemStatus.Disk(mount: mount, name: name, used: used, total: total,
                          usedPercent: nil, isInternal: true, isRemovable: false)
    }

    private func power(adapter: Double? = nil,
                       battery: Double? = nil,
                       system: Double? = nil,
                       onAC: Bool? = nil) -> SystemStatus.Power {
        SystemStatus.Power(adapterWatts: adapter, batteryWatts: battery,
                           systemWatts: system, inputWatts: nil,
                           isCharging: nil, isOnAC: onAC)
    }

    private func status(disks: [SystemStatus.Disk]? = nil,
                        power: SystemStatus.Power? = nil) -> SystemStatus {
        SystemStatus(host: nil, uptime: nil, hardware: nil,
                     healthScore: nil, healthScoreMsg: nil,
                     cpu: nil, gpu: nil, memory: nil, disks: disks,
                     power: power, network: nil, batteries: nil,
                     topProcesses: nil, thermal: nil, collectedAt: nil)
    }

    // MARK: - Disk identity

    /// `ForEach` reads `id` on every render. A UUID fallback would mint a
    /// new identity each time and rebuild the volume row.
    func testDiskIdentityIsStableWhenMountAndNameAreMissing() {
        let volume = disk(mount: nil, name: nil)

        XCTAssertEqual(volume.id, volume.id)
        XCTAssertEqual(volume.id, "disk")
    }

    func testDiskIdentityPrefersMountThenName() {
        XCTAssertEqual(disk(mount: "/Volumes/SSD", name: "SSD").id, "/Volumes/SSD")
        XCTAssertEqual(disk(mount: nil, name: "SSD").id, "SSD")
    }

    // MARK: - Display name

    func testDisplayNamePrefersTheVolumeName() {
        XCTAssertEqual(disk(mount: "/", name: "Macintosh HD").displayName, "Macintosh HD")
    }

    func testDisplayNameCallsTheRootMountTheStartupDisk() {
        XCTAssertEqual(disk(mount: "/", name: nil).displayName, "Startup disk")
        XCTAssertEqual(disk(mount: "/", name: "").displayName, "Startup disk")
    }

    func testDisplayNameFallsBackToTheLastPathComponent() {
        XCTAssertEqual(disk(mount: "/Volumes/Backup", name: nil).displayName, "Backup")
    }

    func testDisplayNameIsADashWhenNothingIsKnown() {
        XCTAssertEqual(disk(mount: nil, name: nil).displayName, "—")
    }

    // MARK: - Free space

    func testFreeSpaceSubtractsUsedFromTotal() {
        XCTAssertEqual(disk(used: 40, total: 100).free, 60)
    }

    /// A used figure that overshoots total is bad data, not negative free
    /// space — the alert copy would otherwise say a volume owes the user bytes.
    func testFreeSpaceNeverGoesNegative() {
        XCTAssertEqual(disk(used: 120, total: 100).free, 0)
    }

    func testFreeSpaceIsUnknownWhenTotalIsMissing() {
        XCTAssertNil(disk(used: 50, total: nil).free)
    }

    func testFreeSpaceIsUnknownWhenUsedIsMissing() {
        XCTAssertNil(disk(used: nil, total: 100).free)
    }

    // MARK: - Primary disk

    func testPrimaryDiskPrefersTheRootMount() {
        let data = disk(mount: "/Volumes/Data", name: "Data")
        let boot = disk(mount: "/", name: "Macintosh HD")

        XCTAssertEqual(status(disks: [data, boot]).primaryDisk?.mount, "/")
    }

    func testPrimaryDiskFallsBackToTheFirstVolume() {
        let data = disk(mount: "/Volumes/Data", name: "Data")

        XCTAssertEqual(status(disks: [data]).primaryDisk?.mount, "/Volumes/Data")
    }

    // MARK: - Headline power

    func testHeadlinePowerPrefersWhatTheMachineIsDrawing() {
        let snapshot = status(power: power(adapter: 70, battery: 8, system: 22, onAC: true))

        XCTAssertEqual(snapshot.headlinePower, 22)
        XCTAssertEqual(snapshot.headlinePowerLabel, "Power draw")
    }

    /// The adapter rating is not draw. It is only the fallback when the
    /// SMC has no system rail, and only while the Mac is on AC.
    func testHeadlinePowerFallsBackToTheAdapterRatingOnAC() {
        let snapshot = status(power: power(adapter: 70, battery: 8, system: nil, onAC: true))

        XCTAssertEqual(snapshot.headlinePower, 70)
        XCTAssertEqual(snapshot.headlinePowerLabel, "Adapter")
    }

    func testHeadlinePowerUsesBatteryDrawOffAC() {
        let snapshot = status(power: power(adapter: 70, battery: 12, system: nil, onAC: false))

        XCTAssertEqual(snapshot.headlinePower, 12)
        XCTAssertEqual(snapshot.headlinePowerLabel, "Battery draw")
    }
}
