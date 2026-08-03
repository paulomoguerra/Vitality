import WidgetKit
import SwiftUI

struct StatusEntry: TimelineEntry {
    let date: Date
    let status: SystemStatus?
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
        let nextUpdate = Date().addingTimeInterval(5 * 60)
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
        .configurationDisplayName("Mac status")
        .description("Live CPU, memory, disk, and power from Mole.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
