import WidgetKit
import SwiftUI

struct StatusEntry: TimelineEntry {
    let date: Date
    let status: SystemStatus?
    /// Set when the shared container has no readable status yet, so the widget
    /// can say why it's empty instead of showing a wall of zeros.
    let isMissingData: Bool
    let isStale: Bool

    /// `date` is WidgetKit's timeline-entry date, not the collection time.
    /// Freshness is evaluated against `SystemStatus.collectedAt` instead.
    init(date: Date, status: SystemStatus?, evaluatedAt: Date = Date()) {
        self.date = date
        self.status = status
        self.isMissingData = (status == nil)
        // Unknown collection time is treated as stale in the presentation. A
        // widget must never label an undated snapshot as live.
        self.isStale = status.map {
            StatusFreshness.state(collectedAt: $0.collectedAt, now: evaluatedAt) == .stale
        } ?? false
    }
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), status: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: Date(), status: SharedStatusStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let now = Date()
        let status = SharedStatusStore.read()
        var entries = [StatusEntry(date: now, status: status, evaluatedAt: now)]

        // WidgetKit snapshots the view. Without a second entry at the stale
        // boundary, a checkmark stays up until the next reload — up to minutes
        // after StatusFreshness.staleAfter.
        if let collectedAt = status?.collectedAt {
            let staleAt = collectedAt.addingTimeInterval(StatusFreshness.staleAfter)
            if staleAt > now {
                entries.append(StatusEntry(date: staleAt, status: status, evaluatedAt: staleAt))
            }
        }

        let policy: TimelineReloadPolicy = entries.count > 1
            ? .atEnd
            : .after(now.addingTimeInterval(2 * 60))
        completion(Timeline(entries: entries, policy: policy))
    }
}

struct SystemStatusWidget: Widget {
    let kind = "SystemStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(Theme.pageBg, for: .widget)
                .preferredColorScheme(.dark)
        }
        .configurationDisplayName("Mac vital signs")
        .description("Health score, CPU, memory, disk and power at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
