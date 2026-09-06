import Foundation
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
            case .normal:   return Theme.statusGood
            case .warning:  return Theme.statusWarn
            case .critical: return Theme.statusCrit
            }
        }

        /// A shape cue keeps status understandable when colour is disabled or
        /// the user has difficulty distinguishing hues.
        var symbolName: String {
            switch self {
            case .normal: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .critical: return "xmark.octagon.fill"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .normal: return "Normal"
            case .warning: return "Warning"
            case .critical: return "Critical"
            }
        }
    }

    static func level(forUsage percent: Double?) -> Level? {
        guard let percent else { return nil }
        if percent >= 90 { return .critical }
        if percent >= 75 { return .warning }
        return .normal
    }

    /// HealthScore has five textual grades but Severity has three colours:
    /// green covers Excellent/Good (75+), orange covers Fair (55–74), and
    /// red covers Poor/Critical (below 55). This keeps the visual warning
    /// level consistent with the grade boundaries without inventing extra
    /// severity cases for the shared UI.
    static func level(forHealth score: Int?) -> Level? {
        guard let score else { return nil }
        if score >= 75 { return .normal }
        if score >= 55 { return .warning }
        return .critical
    }

    /// Apple silicon runs hot by design and only throttles around 100–110°C,
    /// so the thresholds sit well above what a desktop PC would call alarming.
    /// Flagging a perfectly normal 75°C M-series die would train the user to
    /// ignore the colour entirely.
    static func level(forTemperature celsius: Double?) -> Level? {
        guard let celsius else { return nil }
        if celsius >= 95 { return .critical }
        if celsius >= 80 { return .warning }
        return .normal
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
        level(forUsage: percent)?.color ?? Theme.inkSecondary
    }

    static func forCharge(_ percent: Double?) -> Color {
        level(forCharge: percent)?.color ?? Theme.inkSecondary
    }

    static func forHealth(_ score: Int?) -> Color {
        level(forHealth: score)?.color ?? Theme.inkSecondary
    }
}

/// Actions inside a SwiftUI `Table` cannot be `Button`s — AppKit's table
/// eats the click for row selection, so Quit / Open / Trash look live and
/// do nothing. A tap on a labeled control is delivered.
struct TableAction: View {
    let title: String
    var role: ButtonRole? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Text(title)
            .font(.system(size: 11))
            .foregroundStyle(enabled
                             ? (role == .destructive ? Theme.statusCrit : Theme.ink)
                             : Theme.inkFaint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.white.opacity(enabled ? 0.08 : 0.04))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
            .accessibilityHidden(!enabled)
    }
}

struct MiniBar: View {
    let percent: Double?
    var height: CGFloat = 4
    var tint: Color? = nil
    var accessibilityLabel: String? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.progressTrack)
                if let percent {
                    Capsule()
                        .fill(tint ?? Severity.forUsage(percent))
                        .frame(width: geo.size.width * CGFloat(min(max(percent, 0), 100) / 100))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel ?? "Usage"))
        .accessibilityValue(Text(Fmt.percent(percent)))
    }
}

struct HealthRing: View {
    let score: Int?
    var lineWidth: CGFloat = 5

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        ZStack {
            Circle().stroke(
                Theme.progressTrack,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [1, 4])
            )
            Circle()
                .trim(from: 0, to: CGFloat(min(max(score ?? 0, 0), 100)) / 100)
                .stroke(Severity.forHealth(score),
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            dash: [1, differentiateWithoutColor ? 7 : 4]
                        ))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health score")
        .accessibilityValue(Text(score.map { "\($0) out of 100" } ?? "No data"))
    }
}
