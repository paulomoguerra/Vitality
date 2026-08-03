import SwiftUI

/// Shared between the app and the widget extension so a 90%-full disk looks
/// the same red in the menu bar, the dashboard, and on the desktop.
enum Severity {

    /// The judgement behind the colour. The menu bar needs to ask "is this
    /// worth shouting about?" rather than "what colour is it?", so the verdict
    /// and its colour are separate — and every threshold in the app still
    /// lives in exactly one place.
    enum Level {
        case normal, warning, critical

        var color: Color {
            switch self {
            case .normal:   return .green
            case .warning:  return .orange
            case .critical: return .red
            }
        }
    }

    static func level(forUsage percent: Double?) -> Level? {
        guard let percent else { return nil }
        if percent >= 90 { return .critical }
        if percent >= 75 { return .warning }
        return .normal
    }

    /// Thresholds match the grades in `HealthScore`: 90+ "Excellent",
    /// 75–89 "Good", 55–74 "Fair". Keep them in step — a green cutoff that
    /// disagrees with the wording puts an alarmist orange ring next to the
    /// word "Good", the UI contradicting its own label.
    static func level(forHealth score: Int?) -> Level? {
        guard let score else { return nil }
        if score >= 70 { return .normal }
        if score >= 40 { return .warning }
        return .critical
    }

    /// Charge reads the other way round to everything else here: a *low*
    /// battery is the bad one, so it can't go through `forUsage`.
    static func level(forCharge percent: Double?) -> Level? {
        guard let percent else { return nil }
        if percent <= 10 { return .critical }
        if percent <= 20 { return .warning }
        return .normal
    }

    static func forUsage(_ percent: Double?) -> Color {
        level(forUsage: percent)?.color ?? .secondary
    }

    static func forHealth(_ score: Int?) -> Color {
        level(forHealth: score)?.color ?? .secondary
    }
}

struct MiniBar: View {
    let percent: Double?
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(Severity.forUsage(percent))
                    .frame(width: geo.size.width * CGFloat(min(max(percent ?? 0, 0), 100) / 100))
            }
        }
        .frame(height: height)
    }
}

struct HealthRing: View {
    let score: Int?
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(score ?? 0, 0), 100)) / 100)
                .stroke(Severity.forHealth(score),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
