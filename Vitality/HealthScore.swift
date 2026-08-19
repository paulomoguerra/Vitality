import Foundation

/// Vitality's own health score.
///
/// Any single "health" number is a judgement call, so the weights here are
/// deliberately explicit and the score always ships with a message naming the
/// biggest deduction — a bare number the user can't interrogate is worse than
/// no number at all.
///
/// The weighting reflects what actually degrades a Mac, in order: a full boot
/// volume (which breaks installs, updates and swap), sustained swapping, then
/// CPU saturation, then battery wear.
enum HealthScore {

    struct Result {
        let score: Int?
        let message: String
    }

    private struct Deduction {
        let amount: Int
        let reason: String
    }

    static func evaluate(cpu: SystemStatus.CPU?,
                         memory: SystemStatus.Memory?,
                         disk: SystemStatus.Disk?,
                         battery: SystemStatus.Battery?) -> Result {
        // A score without the three primary signals is not a measurement —
        // it is just the absence of deductions, which would misleadingly
        // render as 100/Excellent. Battery is deliberately not required:
        // desktop Macs do not expose one.
        guard cpu?.usage != nil,
              memory?.swapUsed != nil,
              memory?.swapTotal != nil,
              disk?.usedPercent != nil else {
            return Result(score: nil, message: "Limited data")
        }

        var deductions: [Deduction] = []

        if let used = disk?.usedPercent {
            switch used {
            case 95...:    deductions.append(.init(amount: 28, reason: "Disk critically full"))
            case 90..<95:  deductions.append(.init(amount: 20, reason: "Disk almost full"))
            case 85..<90:  deductions.append(.init(amount: 10, reason: "Disk filling up"))
            case 75..<85:  deductions.append(.init(amount: 4,  reason: "Disk getting full"))
            default: break
            }
        }

        // Swapping is the honest signal for memory trouble. macOS keeps RAM
        // deliberately full, so a high "memory used" figure on its own is
        // normal and penalising it would flag every healthy Mac.
        if let used = memory?.swapUsed, let total = memory?.swapTotal, total > 0 {
            switch Double(used) / Double(total) {
            case 0.75...:      deductions.append(.init(amount: 16, reason: "Heavy swapping"))
            case 0.45..<0.75:  deductions.append(.init(amount: 9,  reason: "Swapping to disk"))
            case 0.2..<0.45:   deductions.append(.init(amount: 3,  reason: "Light swapping"))
            default: break
            }
        }

        if let usage = cpu?.usage {
            switch usage {
            case 90...:    deductions.append(.init(amount: 12, reason: "CPU saturated"))
            case 75..<90:  deductions.append(.init(amount: 5,  reason: "CPU under load"))
            default: break
            }
        }

        // Load average relative to core count catches sustained pressure that
        // an instantaneous CPU reading misses.
        if let load = cpu?.load5, let cores = cpu?.coreCount, cores > 0 {
            let ratio = load / Double(cores)
            if ratio >= 1.5 { deductions.append(.init(amount: 8, reason: "System overloaded")) }
            else if ratio >= 1.0 { deductions.append(.init(amount: 4, reason: "System busy")) }
        }

        if let capacity = battery?.capacity {
            switch capacity {
            case ..<70:   deductions.append(.init(amount: 12, reason: "Battery worn"))
            case 70..<80: deductions.append(.init(amount: 6,  reason: "Battery ageing"))
            default: break
            }
        }

        let score = max(0, min(100, 100 - deductions.reduce(0) { $0 + $1.amount }))
        return Result(score: score, message: message(for: score, deductions: deductions))
    }

    private static func message(for score: Int, deductions: [Deduction]) -> String {
        let grade: String
        switch score {
        case 90...:   grade = "Excellent"
        case 75..<90: grade = "Good"
        case 55..<75: grade = "Fair"
        case 35..<55: grade = "Poor"
        default:      grade = "Critical"
        }

        // Name the single biggest problem rather than listing everything —
        // one actionable sentence beats an accurate but unreadable list.
        guard let worst = deductions.max(by: { $0.amount < $1.amount }) else {
            return grade
        }
        return "\(grade): \(worst.reason)"
    }
}
