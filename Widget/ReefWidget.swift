import WidgetKit
import SwiftUI

struct ReefProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReefEntry { ReefEntry(date: .now, snapshot: ReefCache.read()) }
    func getSnapshot(in context: Context, completion: @escaping (ReefEntry) -> Void) { completion(ReefEntry(date: .now, snapshot: ReefCache.read())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ReefEntry>) -> Void) {
        Task {
            let snapshot: ReefSnapshot?
            if let tank: Tank = try? await ReefAPI.get("tank"), let metrics: [Metric] = try? await ReefAPI.get("metrics"), let reminders: [ReefReminder] = try? await ReefAPI.get("reminders") {
                snapshot = ReefSnapshot(tankName: tank.name, metrics: metrics, reminders: reminders)
                ReefCache.save(snapshot!)
            } else { snapshot = ReefCache.read() }
            completion(Timeline(entries: [ReefEntry(date: .now, snapshot: snapshot)], policy: .after(Date().addingTimeInterval(1800))))
        }
    }
}
struct ReefEntry: TimelineEntry { let date: Date; let snapshot: ReefSnapshot? }
struct ReefWidgetView: View {
    let entry: ReefEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(entry.snapshot?.tankName ?? "Reef Log", systemImage: "water.waves").font(.headline).lineLimit(1)
            if let snapshot = entry.snapshot {
                ForEach(Array(snapshot.metrics.prefix(3))) { metric in
                    HStack { Text(metric.name).lineLimit(1); Spacer(); Text(metric.lastValue.map { $0.formatted() } ?? "—").monospacedDigit(); Text(metric.unit).foregroundStyle(.secondary) }
                        .font(.subheadline)
                }
                if snapshot.metrics.isEmpty { Text("No water readings yet").foregroundStyle(.secondary) }
            } else { Text("Open Reef Log to sync").foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
struct ReefSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReefSummary", provider: ReefProvider()) { ReefWidgetView(entry: $0) }
            .configurationDisplayName("Reef Readings")
            .description("Recent water parameters from Reef Log.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
