import XCTest

/// The health score is Vitality's own judgement, not a reading — which is
/// exactly why it is worth pinning down. The number and the sentence beside it
/// are the first thing anyone sees, and a refactor that quietly shifts a
/// threshold changes what the app tells people about their Mac.
final class HealthScoreTests: XCTestCase {

    // MARK: - Builders

    private func cpu(usage: Double? = 5,
                     load5: Double? = 1,
                     cores: Int? = 8) -> SystemStatus.CPU {
        SystemStatus.CPU(usage: usage, perCore: nil, load1: nil, load5: load5, load15: nil,
                         coreCount: cores, pCoreCount: nil, eCoreCount: nil)
    }

    private func memory(swapUsed: Int64? = 0,
                        swapTotal: Int64? = 4_000_000_000) -> SystemStatus.Memory {
        SystemStatus.Memory(used: nil, total: nil, available: nil, usedPercent: nil,
                            swapUsed: swapUsed, swapTotal: swapTotal, cached: nil, pressure: nil)
    }

    private func disk(usedPercent: Double?) -> SystemStatus.Disk {
        SystemStatus.Disk(mount: "/", name: nil, used: nil, total: nil,
                          usedPercent: usedPercent, isInternal: true, isRemovable: false)
    }

    private func battery(capacity: Int?) -> SystemStatus.Battery {
        SystemStatus.Battery(percent: nil, status: nil, timeLeft: nil,
                             health: nil, cycleCount: nil, capacity: capacity)
    }

    private func evaluate(cpu: SystemStatus.CPU? = nil,
                          memory: SystemStatus.Memory? = nil,
                          disk: SystemStatus.Disk? = nil,
                          battery: SystemStatus.Battery? = nil) -> HealthScore.Result {
        HealthScore.evaluate(cpu: cpu ?? self.cpu(),
                             memory: memory ?? self.memory(),
                             disk: disk ?? self.disk(usedPercent: 40),
                             battery: battery)
    }

    // MARK: - Missing data

    /// The distinction the whole design rests on: no signals means "we don't
    /// know", not "everything is fine". A missing measurement must never
    /// render as a perfect score.
    func testReportsLimitedDataRatherThanAPerfectScore() {
        let result = HealthScore.evaluate(cpu: nil, memory: nil, disk: nil, battery: nil)

        XCTAssertNil(result.score)
        XCTAssertEqual(result.message, "Limited data")
    }

    func testEachPrimarySignalIsRequired() {
        XCTAssertNil(evaluate(cpu: cpu(usage: nil)).score, "CPU usage is required")
        XCTAssertNil(evaluate(memory: memory(swapUsed: nil)).score, "swap used is required")
        XCTAssertNil(evaluate(disk: disk(usedPercent: nil)).score, "disk usage is required")
    }

    /// Desktop Macs have no battery. Requiring one would leave every iMac and
    /// Mac mini permanently on "Limited data".
    func testBatteryIsNotRequired() {
        XCTAssertEqual(evaluate(battery: nil).score, 100)
    }

    // MARK: - Scoring

    func testHealthyMacScoresFull() {
        let result = evaluate()

        XCTAssertEqual(result.score, 100)
        XCTAssertEqual(result.message, "Excellent")
    }

    func testDeductionsAccumulate() {
        let result = evaluate(cpu: cpu(usage: 95, load5: 1),
                              disk: disk(usedPercent: 96))

        // 28 for a critically full disk, 12 for a saturated CPU.
        XCTAssertEqual(result.score, 60)
    }

    func testScoreNeverGoesBelowZero() {
        let result = evaluate(cpu: cpu(usage: 100, load5: 40),
                              memory: memory(swapUsed: 4_000_000_000),
                              disk: disk(usedPercent: 99),
                              battery: battery(capacity: 50))

        let score = try? XCTUnwrap(result.score)
        XCTAssertGreaterThanOrEqual(score ?? -1, 0)
    }

    // MARK: - The message

    /// The score ships with the single biggest deduction named, so the number
    /// can be interrogated rather than just trusted.
    func testMessageNamesTheBiggestDeductionNotTheFirst() {
        // CPU under load (5) is evaluated after the disk (20), and the disk is
        // the heavier problem — that is the one worth saying out loud.
        let result = evaluate(cpu: cpu(usage: 80, load5: 1),
                              disk: disk(usedPercent: 92))

        XCTAssertEqual(result.score, 75)
        XCTAssertEqual(result.message, "Good: Disk almost full")
    }

    /// The grade comes from the score, so a small deduction still reads as
    /// "Excellent" while naming what it found. That is deliberate: the grade
    /// answers "how is the Mac", the clause answers "what did you notice".
    func testGradeTracksTheScore() {
        XCTAssertEqual(evaluate().message, "Excellent")
        XCTAssertEqual(evaluate(disk: disk(usedPercent: 88)).message, "Excellent: Disk filling up")
        XCTAssertEqual(evaluate(disk: disk(usedPercent: 96)).message, "Fair: Disk critically full")
    }

    // MARK: - Deliberate non-deductions

    /// macOS keeps RAM deliberately full, so a high "memory used" figure is
    /// normal. Swapping is the signal the score is allowed to react to.
    func testHighMemoryUseWithoutSwappingIsNotPenalised() {
        let full = SystemStatus.Memory(used: 15_000_000_000, total: 16_000_000_000,
                                       available: 1_000_000_000, usedPercent: 94,
                                       swapUsed: 0, swapTotal: 4_000_000_000,
                                       cached: nil, pressure: nil)

        XCTAssertEqual(evaluate(memory: full).score, 100)
    }

    func testLoadIsJudgedAgainstCoreCount() {
        // A load of 8 is a busy machine on 8 cores and an idle one on 16.
        XCTAssertEqual(evaluate(cpu: cpu(usage: 5, load5: 8, cores: 8)).score, 96)
        XCTAssertEqual(evaluate(cpu: cpu(usage: 5, load5: 8, cores: 16)).score, 100)
    }

    func testSwappingIsScaledNotBinary() {
        XCTAssertEqual(evaluate(memory: memory(swapUsed: 1_200_000_000)).score, 97,
                       "light swapping costs 3")
        XCTAssertEqual(evaluate(memory: memory(swapUsed: 2_400_000_000)).score, 91,
                       "sustained swapping costs 9")
        XCTAssertEqual(evaluate(memory: memory(swapUsed: 3_600_000_000)).score, 84,
                       "heavy swapping costs 16")
    }
}
