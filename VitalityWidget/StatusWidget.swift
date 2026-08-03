import WidgetKit
import SwiftUI

struct StatusEntry: TimelineEntry {
    let date: Date
    let status: SystemStatus?
    /// Set when the shared container has no readable status yet, so the widget
    /// can say why it's empty instead of showing a wall of zeros.
    let isMissingData: Bool

    init(date: Date, status: SystemStatus?) {
        self.date = date
        self.status = status
        self.isMissingData = (status == nil)
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
        let entry = StatusEntry(date: Date(), status: SharedStatusStore.read())

        // The app calls `WidgetCenter.reloadAllTimelines()` roughly every 30s
        // while it's running, which is the real refresh path. This shorter
        // fallback only matters if the app isn't running — in which case the
        // data is stale anyway and there's nothing to gain from asking sooner.
        let nextUpdate = Date().addingTimeInterval(2 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct SystemStatusWidget: Widget {
    let kind = "SystemStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mac vital signs")
        .description("Health score, CPU, memory, disk and power at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
