import SwiftUI

/// How a history series maps onto the chart's vertical axis.
enum ChartScale {
    /// Fixed 0–100 ceiling, so a steady 20% line sits low instead of filling
    /// the frame and shouting.
    case percent
    /// No natural ceiling (watts, bytes/s) — plotted against the window's own
    /// maximum with 25% headroom, making it a shape-of-the-period graph.
    case relative
}

/// An area-line chart over persisted history, with a hover crosshair.
///
/// X is mapped by *time*, not by sample index: the store commits a bucket only
/// while the app runs, so an overnight gap would otherwise be silently
/// compressed into nothing and the morning spike would look adjacent to last
/// evening's.
struct HistoryChart: View, Equatable {
    let points: [HistoryPoint]
    let scale: ChartScale
    let tint: Color
    var height: CGFloat = 64
    /// Formats the hovered value ("42%", "8.4 MB/s").
    var format: (Double) -> String = { String(format: "%.0f%%", $0) }
    /// 24 h / 7 d hovers need a calendar date; the 1 h view does not.
    var showsCalendarDate = false

    @State private var hoverLocation: CGPoint?

    /// The parents of these charts observe the 1 Hz poller for their headline
    /// numbers, so their bodies re-evaluate every second. The series only
    /// changes when a bucket commits (at most every 5 s), and rebuilding a
    /// 1,440-segment Path a second to draw the same picture is exactly the
    /// kind of idle cost Vitality exists to point at. Used via `.equatable()`;
    /// `format` is deliberately left out — it is fixed per call site.
    static func == (lhs: HistoryChart, rhs: HistoryChart) -> Bool {
        lhs.points == rhs.points && lhs.scale == rhs.scale
            && lhs.tint == rhs.tint && lhs.height == rhs.height
            && lhs.showsCalendarDate == rhs.showsCalendarDate
    }

    var body: some View {
        GeometryReader { geo in
            let layout = layout(in: geo.size)
            ZStack(alignment: .topLeading) {
                grid(in: geo.size)
                if layout.count > 1 {
                    area(layout, in: geo.size).fill(tint.opacity(0.14))
                    line(layout)
                        .stroke(tint.opacity(0.9),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if let hover = hoverInfo(layout: layout, size: geo.size) {
                    crosshair(hover, in: geo.size)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoverLocation = location
                case .ended: hoverLocation = nil
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    // MARK: - Geometry

    private func layout(in size: CGSize) -> [CGPoint] {
        guard let first = points.first, let last = points.last else { return [] }
        let span = last.date.timeIntervalSince(first.date)

        let ceiling: Double
        switch scale {
        case .percent:
            ceiling = 100
        case .relative:
            ceiling = max((points.map(\.value).max() ?? 1) * 1.25, 0.001)
        }

        // Half the stroke inset top and bottom so a 0% or 100% line isn't
        // shaved in half by the frame.
        let usable = max(size.height - 2, 1)
        return points.map { point in
            let x = span > 0
                ? size.width * CGFloat(point.date.timeIntervalSince(first.date) / span)
                : size.width / 2
            let fraction = min(max(point.value / ceiling, 0), 1)
            return CGPoint(x: x, y: 1 + usable * (1 - CGFloat(fraction)))
        }
    }

    private func line(_ pts: [CGPoint]) -> Path {
        Path { path in
            path.move(to: pts[0])
            for pt in pts.dropFirst() { path.addLine(to: pt) }
        }
    }

    private func area(_ pts: [CGPoint], in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: pts[0].x, y: size.height))
            for pt in pts { path.addLine(to: pt) }
            path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: size.height))
            path.closeSubpath()
        }
    }

    private func grid(in size: CGSize) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            path.move(to: CGPoint(x: 0, y: size.height - 0.5))
            path.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
        }
        .stroke(Theme.grid, lineWidth: 1)
    }

    // MARK: - Hover

    private struct Hover {
        let point: CGPoint
        let value: Double
        let date: Date
    }

    private func hoverInfo(layout: [CGPoint], size: CGSize) -> Hover? {
        guard let location = hoverLocation, layout.count > 1 else { return nil }
        // Nearest sample by x — the hit target is the whole chart, far bigger
        // than the 2pt line itself.
        var best = 0
        var bestDistance = CGFloat.infinity
        for (index, pt) in layout.enumerated() {
            let distance = abs(pt.x - location.x)
            if distance < bestDistance { bestDistance = distance; best = index }
        }
        return Hover(point: layout[best], value: points[best].value, date: points[best].date)
    }

    @ViewBuilder
    private func crosshair(_ hover: Hover, in size: CGSize) -> some View {
        Path { path in
            path.move(to: CGPoint(x: hover.point.x, y: 0))
            path.addLine(to: CGPoint(x: hover.point.x, y: size.height))
        }
        .stroke(Theme.inkFaint, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        Circle()
            .fill(tint)
            .stroke(Theme.cardBg, lineWidth: 2)
            .frame(width: 9, height: 9)
            .position(hover.point)

        Text("\(hover.date, format: hoverDateFormat)  \(format(hover.value))")
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline))
            // Clamp the bubble inside the chart instead of letting it clip at
            // either edge.
            .position(x: min(max(hover.point.x, hoverGutter), size.width - hoverGutter), y: 12)
    }

    private var hoverDateFormat: Date.FormatStyle {
        showsCalendarDate
            ? .dateTime.month(.abbreviated).day().hour().minute()
            : .dateTime.hour().minute()
    }

    private var hoverGutter: CGFloat { showsCalendarDate ? 88 : 55 }
}

/// A dashboard metric card: headline value, history chart, average/peak footer.
struct HistoryChartCard: View {
    let label: String
    let currentText: String
    var subtitle: String?
    let points: [HistoryPoint]
    let scale: ChartScale
    let tint: Color
    var accessibilityRange: String? = nil
    /// (average, peak) over the visible range, from the store's per-bucket
    /// maxima — a peak recomputed from bucket averages would understate spikes.
    var stats: (average: Double, peak: Double)?
    var format: (Double) -> String = { String(format: "%.0f%%", $0) }
    var showsCalendarDate = false
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                // A Button wrapping the chart loses clicks on macOS — the
                // hover surface eats them. The card still looks like a
                // control; the tap is on the card, not an inner NSButton.
                content
                    .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .simultaneousGesture(TapGesture().onEnded(action))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(label)
                    .accessibilityValue(accessibilitySummary)
                    .accessibilityHint("Opens related details")
            } else {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                    .accessibilityValue(accessibilitySummary)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                Text(currentText)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .accessibilityHidden(true)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
            }
            if points.count > 1 {
                HistoryChart(points: points, scale: scale, tint: tint, format: format,
                             showsCalendarDate: showsCalendarDate)
                    .equatable()
            } else {
                // A brand-new install has no committed buckets yet. Say so
                // rather than drawing an empty box that looks broken.
                Text("Collecting history…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            if let stats {
                HStack {
                    Text("avg \(format(stats.average))")
                    Spacer()
                    Text("peak \(format(stats.peak))")
                }
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.inkTertiary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThemeCardBackground(radius: Theme.cardRadius))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var accessibilitySummary: String {
        var parts = ["Current \(currentText)"]
        if let accessibilityRange { parts.append("History range \(accessibilityRange)") }
        if let subtitle { parts.append(subtitle) }
        if let stats {
            parts.append("Average \(format(stats.average))")
            parts.append("Peak \(format(stats.peak))")
        } else {
            parts.append("History is still being collected")
        }
        return parts.joined(separator: ". ")
    }
}

/// The 1 h · 24 h · 7 d control every history chart follows.
struct RangePicker: View {
    @Binding var range: HistoryRange

    var body: some View {
        Picker("Range", selection: $range) {
            ForEach(HistoryRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}
