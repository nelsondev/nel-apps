import SwiftUI

@main
struct NelApps: App {
    var body: some Scene { WindowGroup { NelAppsHome() } }
}

struct NelAppsHome: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { GroceryView().toolbar(.hidden, for: .tabBar) } label: {
                        VStack(alignment: .leading, spacing: 3) { Text("Groceries").font(.headline); Text("Shopping list and Live Activity").font(.subheadline).foregroundStyle(.secondary) }
                            .padding(.vertical, 8)
                    }
                    NavigationLink { ReefRootView() } label: {
                        VStack(alignment: .leading, spacing: 3) { Text("Reef Log").font(.headline); Text("Water testing, trends and maintenance").font(.subheadline).foregroundStyle(.secondary) }
                            .padding(.vertical, 8)
                    }
                } header: { Text("Your apps") }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("NelApps")
        }
    }
}
