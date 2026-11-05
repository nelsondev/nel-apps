import ActivityKit
import AppIntents
import WidgetKit

struct BuyItemIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark grocery purchased"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Grocery ID") var itemID: Int

    init() {}
    init(itemID: Int) { self.itemID = itemID }

    func perform() async throws -> some IntentResult {
        try await GroceryAPI.buy(itemID)

        let activities = Activity<GroceryActivityAttributes>.activities
        for activity in activities {
            let remaining = activity.content.state.items.filter { $0.id != itemID }
            await activity.update(ActivityContent(state: .init(items: remaining), staleDate: nil))
        }

        var cached = GroceryCache.read()
        cached.removeAll { $0.id == itemID }
        GroceryCache.save(cached)
        WidgetCenter.shared.reloadAllTimelines()

        if let items = try? await GroceryAPI.list() {
            GroceryCache.save(items)
            let state = GroceryActivityAttributes.ContentState(items: items.map { .init(id: $0.id, name: $0.name) })
            for activity in Activity<GroceryActivityAttributes>.activities {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
        return .result()
    }
}
