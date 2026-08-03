import SwiftUI

/// The strip of live figures drawn inside the status item button, and in the
/// settings pane's preview.
///
/// Everything here is sized to the 22pt menu bar: 11pt figures, 9pt tags, and
/// a graph small enough that three chips still leave room for the rest of the
/// user's menu bar.
///
/// Nothing in this file knows about `NSStatusItem`, the poller, or the history
/// store — which is what lets the same view be rendered straight to an image
/// to check the design.
///
/// History arrives as a lookup rather than the `MenuBarHistory` object: the
/// strip only needs the numbers, and whoever hands them over is already
/// observing the store, so the redraw happens either way.
struct MenuBarStrip: View {
    let status: SystemStatus?
    @ObservedObject var settings: MenuBarSettings
    let samples: (MenuBarMetric) -> [Double]

    var body: some View {
        HStack(spacing: 9) {
            if settings.showsAppIconEffective {
                Image(systemName: "gauge.medium")
                    .font(.system(size: 14))
            }

            ForEach(settings.displayedMetrics) { metric in
                MenuBarChip(metric: metric,
                            reading: metric.reading(from: status),
                            samples: samples(metric),
                            settings: settings)
            }
        }
        .padding(.horizontal, 5)
    }
}

private struct MenuBarChip: View {
    let metric: MenuBarMetric
    let reading: MenuBarMetric.Reading
    let samples: [Double]
    @ObservedObject var settings: MenuBarSettings

    var body: some View {
        // Two copies: an invisible one at this metric's widest possible reading
        // to claim the space, and the real one right-aligned inside it.
        //
        // Reserving the room matters — without it, CPU crossing 9% → 10% shoves
        // every chip to its right sideways once a second. But reserving it
        // *inside* the value alone strands "3%" two characters away from its
        // own "GPU" tag. Sizing the whole chip and packing it to the right
        // instead puts the slack between chips, where a gap looks deliberate.
        ZStack(alignment: .trailing) {
            content(value: metric.widestValue, drawGraph: false).hidden()
            content(value: reading.text, drawGraph: true)
        }
    }

    @ViewBuilder
    private func content(value: String, drawGraph: Bool) -> some View {
        let tint = settings.tint(for: reading.level)

        HStack(spacing: 4) {
            if settings.showsLabels {
                Text(metric.shortLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if settings.showsGraph && metric.isGraphable {
                Group {
                    if drawGraph {
                        MenuBarSparkline(samples: samples,
                                         scale: reading.scale,
                                         tint: tint ?? .primary)
                    }
                }
                .frame(width: 24, height: 11)
            }

            Text(value)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(tint ?? .primary)
        }
    }
}

/// A 40-second area chart, drawn small.
struct MenuBarSparkline: View {
    let samples: [Double]
    let scale: MenuBarMetric.Reading.Scale
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let points = points(in: geo.size)
            if points.count > 1 {
                ZStack {
                    area(through: points, in: geo.size).fill(tint.opacity(0.16))
                    line(through: points)
                        .stroke(tint.opacity(0.9),
                                style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard !samples.isEmpty else { return [] }
        // One sample is still worth drawing — as a flat line, not an empty box.
        let series = samples.count == 1 ? [samples[0], samples[0]] : samples

        let ceiling: Double
        switch scale {
        case .percent:
            ceiling = 100
        case .relative:
            // 25% headroom, so a steady figure sits high rather than pinned to
            // the very top edge looking like it has maxed something out.
            ceiling = max((series.max() ?? 1) * 1.25, 0.001)
        }

        // Half a point of inset top and bottom keeps a 1pt stroke inside the
        // frame at 0% and 100% instead of shaving it in half.
        let top: CGFloat = 0.5
        let usableHeight = max(size.height - 1, 1)
        let step = size.width / CGFloat(series.count - 1)

        return series.enumerated().map { index, value in
            let fraction = min(max(value / ceiling, 0), 1)
            return CGPoint(x: CGFloat(index) * step,
                           y: top + usableHeight * (1 - CGFloat(fraction)))
        }
    }

    private func line(through points: [CGPoint]) -> Path {
        Path { path in
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    private func area(through points: [CGPoint], in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: points[0].x, y: size.height))
            for point in points { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
            path.closeSubpath()
        }
    }
}
