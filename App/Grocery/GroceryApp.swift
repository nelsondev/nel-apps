
import SwiftUI
import ActivityKit
import WidgetKit

@MainActor
@Observable final class GroceryStore {
    var items: [GroceryItem] = GroceryCache.read()
    var entry = ""
    var error: String?
    var entryNotice: String?
    var busy = false
    var activityActive = false

    func refresh() async {
        do {
            items = try await GroceryAPI.list()
            GroceryCache.save(items)
            WidgetCenter.shared.reloadAllTimelines()
            await updateActivity()
        } catch {
            self.error = "Cannot reach grocery.home.lab: \(error.localizedDescription)"
        }
    }

    func add() async {
        let name = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !busy else { return }
        if items.contains(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            entryNotice = "\(name) is already on your list."
            return
        }
        entryNotice = nil
        busy = true
        defer { busy = false }
        do {
            try await GroceryAPI.add(name)
            entry = ""
            await refresh()
        } catch let apiError as GroceryAPI.APIError {
            if apiError.statusCode == 409 {
                entryNotice = "\(name) is already on your list."
                await refresh()
            } else {
                self.error = apiError.localizedDescription
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func buy(_ id: Int) async {
        do {
            try await GroceryAPI.buy(id)
            items.removeAll { $0.id == id }
            GroceryCache.save(items)
            await updateActivity()
            WidgetCenter.shared.reloadAllTimelines()
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ id: Int) async {
        do {
            try await GroceryAPI.delete(id)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func finish() async {
        do {
            try await GroceryAPI.completeAll()
            await endActivity()
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startActivity() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            self.error = "Enable Live Activities for Groceries in Settings."
            return
        }
        guard !items.isEmpty else { return }
        do {
            await endActivity()
            let state = GroceryActivityAttributes.ContentState(items: items.map { .init(id: $0.id, name: $0.name) })
            _ = try Activity.request(attributes: GroceryActivityAttributes(title: "Shopping List"), content: .init(state: state, staleDate: nil), pushType: nil)
            activityActive = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateActivity() async {
        let state = GroceryActivityAttributes.ContentState(items: items.map { .init(id: $0.id, name: $0.name) })
        for activity in Activity<GroceryActivityAttributes>.activities {
            await activity.update(.init(state: state, staleDate: nil))
        }
        activityActive = !Activity<GroceryActivityAttributes>.activities.isEmpty
    }

    func endActivity() async {
        for activity in Activity<GroceryActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activityActive = false
    }
}

struct GroceryView: View {
    @State private var store = GroceryStore()
    @State private var confirmFinish = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                GroceryEntrySection(store: store)
                GroceryItemsSection(store: store)
                GroceryShoppingSection(store: store, confirmFinish: $confirmFinish)
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
            .navigationTitle("Groceries")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await store.refresh() }
                    }
                }
            }
            .refreshable { await store.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.refresh() } }
            }
            .task {
                await store.refresh()
                store.activityActive = !Activity<GroceryActivityAttributes>.activities.isEmpty
            }
            .alert("Finish shopping?", isPresented: $confirmFinish) {
                Button("Mark all purchased") { Task { await store.finish() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All remaining items will be added to your purchase history.")
            }
            .alert("Grocery error", isPresented: Binding(
                get: { store.error != nil },
                set: { if !$0 { store.error = nil } }
            )) {
                Button("OK") { store.error = nil }
            } message: {
                Text(store.error ?? "")
            }
        }
    }
}

struct GroceryEntrySection: View {
    @Bindable var store: GroceryStore
    @FocusState private var entryFocused: Bool

    private var canAdd: Bool {
        !store.busy && !store.entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Section {
            HStack(spacing: 12) {
                TextField("Add an item", text: $store.entry)
                    .onChange(of: store.entry) { _, _ in store.entryNotice = nil }
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($entryFocused)
                    .onSubmit { Task { await store.add() } }

                Button {
                    Task { await store.add() }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .disabled(!canAdd)
                .accessibilityLabel("Add item")
            }
            if let notice = store.entryNotice {
                Label(notice, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct GroceryItemsSection: View {
    var store: GroceryStore

    var body: some View {
        Section {
            if store.items.isEmpty {
                ContentUnavailableView(
                    "Nothing to buy",
                    systemImage: "checkmark.circle",
                    description: Text("Add an item to start your list.")
                )
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.items) { item in
                    GroceryItemRow(item: item, store: store)
                }
            }
        } header: {
            Text("To buy")
        } footer: {
            if !store.items.isEmpty {
                Text("Tap a circle to mark an item purchased. Swipe left to delete.")
            }
        }
    }
}

struct GroceryItemRow: View {
    let item: GroceryItem
    var store: GroceryStore

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Task { await store.buy(item.id) }
            } label: {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Mark \(item.name) purchased")

            Text(item.name)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await store.delete(item.id) }
            }
        }
        .swipeActions(edge: .leading) {
            Button("Purchased", systemImage: "checkmark") {
                Task { await store.buy(item.id) }
            }
            .tint(.green)
        }
    }
}

struct GroceryShoppingSection: View {
    var store: GroceryStore
    @Binding var confirmFinish: Bool

    var body: some View {
        Section {
            Button {
                Task {
                    if store.activityActive {
                        await store.endActivity()
                    } else {
                        await store.startActivity()
                    }
                }
            } label: {
                Label(
                    store.activityActive ? "End shopping session" : "Start shopping session",
                    systemImage: store.activityActive ? "stop.circle" : "play.circle"
                )
            }
            .disabled(store.items.isEmpty && !store.activityActive)

            Button(role: .destructive) {
                confirmFinish = true
            } label: {
                Label("Finish shopping", systemImage: "checkmark.circle")
            }
            .disabled(store.items.isEmpty)
        } header: {
            Text("Shopping")
        } footer: {
            Text("A shopping session shows your next three items on the Lock Screen.")
        }
    }
}
