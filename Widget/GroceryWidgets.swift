import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

struct GroceryEntry: TimelineEntry { let date: Date; let items: [GroceryItem] }

struct GroceryProvider: TimelineProvider {
    func placeholder(in context: Context) -> GroceryEntry { GroceryEntry(date: .now, items: [GroceryItem(id: 1, name: "Potatoes"), GroceryItem(id: 2, name: "Onions")]) }
    func getSnapshot(in context: Context, completion: @escaping (GroceryEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GroceryEntry>) -> Void) {
        Task {
            let items = (try? await GroceryAPI.list()) ?? GroceryCache.read()
            completion(Timeline(entries: [GroceryEntry(date: .now, items: items)], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
}


struct GroceryWidget: Widget {
    let kind = "GroceryWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GroceryProvider()) { entry in
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Groceries").font(.headline); Spacer(); Text("\(entry.items.count)").foregroundStyle(.secondary) }
                ForEach(entry.items.prefix(5)) { item in
                    Button(intent: BuyItemIntent(itemID: item.id)) {
                        Label(item.name, systemImage: "circle").font(.subheadline).lineLimit(1)
                    }.buttonStyle(.plain)
                }
                if entry.items.isEmpty { Text("All caught up").foregroundStyle(.secondary) }
                if entry.items.count > 5 { Text("+\(entry.items.count - 5) more").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            .padding()
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Grocery List")
        .description("Your shared grocery list, with quick purchase buttons.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct GroceryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GroceryActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Shopping List", systemImage: "basket")
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text("\(context.state.items.count) remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if context.state.items.isEmpty {
                    Label("All caught up", systemImage: "checkmark.circle")
                        .font(.subheadline)
                } else {
                    ForEach(context.state.items.prefix(3), id: \.id) { item in
                        Button(intent: BuyItemIntent(itemID: item.id)) {
                            HStack(spacing: 10) {
                                Image(systemName: "circle").foregroundStyle(.secondary)
                                Text(item.name).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 24)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("Groceries") }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.items.count) left") }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.items.prefix(3).map(\.name).joined(separator: " · ")).lineLimit(2) }
            } compactLeading: { Image(systemName: "basket") } compactTrailing: { Text("\(context.state.items.count)") } minimal: { Image(systemName: "basket") }
        }
    }
}

