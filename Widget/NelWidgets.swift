import WidgetKit
import SwiftUI

@main
struct NelWidgetBundle: WidgetBundle {
    var body: some Widget {
        GroceryWidget()
        GroceryLiveActivity()
        ReefSummaryWidget()
    }
}
