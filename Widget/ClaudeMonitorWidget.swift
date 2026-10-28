import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    var date: Date
    var snapshot: UsageSnapshot?
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: .now, snapshot: SharedStore.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        // The host app pushes reloads after each fetch; this is only a fallback.
        let entry = UsageEntry(date: .now, snapshot: SharedStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct ClaudeMonitorWidgetView: View {
    var entry: UsageEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                UsageCard(snapshot: snapshot)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.title2)
                    Text("Open Claude Monitor to start")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            }
        }
        .widgetURL(URL(string: "claudemonitor://open"))
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct ClaudeMonitorWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: UsageProvider()) { entry in
            ClaudeMonitorWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Remaining Claude limits and token usage.")
        .supportedFamilies([.systemMedium])
    }
}

#Preview(as: .systemMedium) {
    ClaudeMonitorWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .placeholder)
}
