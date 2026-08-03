import SwiftUI

/// Shared between the app and the widget extension so a 90%-full disk looks
/// the same red in the menu bar, the dashboard, and on the desktop.
enum Severity {
    static func forUsage(_ percent: Double?) -> Color {
        guard let percent else { return .secondary }
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        return .green
    }

    /// Thresholds deliberately match Mole's own wording: it grades ~85+ as
    /// "Excellent" and roughly 70–84 as "Good". Using 80 as the green cutoff
    /// put an alarmist orange ring next to the word "Good" — the UI
    /// contradicting its own label.
    static func forHealth(_ score: Int?) -> Color {
        guard let score else { return .secondary }
        if score >= 70 { return .green }
        if score >= 40 { return .orange }
        return .red
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
