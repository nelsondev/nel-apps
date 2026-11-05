import ActivityKit
import Foundation

struct GroceryActivityAttributes: ActivityAttributes {
    struct Item: Codable, Hashable { let id: Int; let name: String }
    struct ContentState: Codable, Hashable { var items: [Item] }
    var title: String
}
