import SwiftUI
import UserNotifications
import WidgetKit

@MainActor @Observable final class ReefStore {
    var tank = Tank(id: 1, name: ReefCache.read()?.tankName ?? "My Reef")
    var metrics: [Metric] = ReefCache.read()?.metrics ?? []
    var reminders: [ReefReminder] = ReefCache.read()?.reminders ?? []
    var trends: [Trend] = []
    var loading = false
    var error: String?
    func refresh() async {
        loading = true; defer { loading = false }
        do {
            async let tankResult: Tank = ReefAPI.get("tank")
            async let metricResult: [Metric] = ReefAPI.get("metrics")
            async let reminderResult: [ReefReminder] = ReefAPI.get("reminders")
            async let trendResult: [Trend] = ReefAPI.get("trends")
            (tank, metrics, reminders, trends) = try await (tankResult, metricResult, reminderResult, trendResult)
            ReefCache.save(ReefSnapshot(tankName: tank.name, metrics: metrics, reminders: reminders))
            WidgetCenter.shared.reloadAllTimelines()
            await scheduleNotifications()
        } catch { self.error = error.localizedDescription }
    }
    func execute(_ action: @escaping () async throws -> Void) async {
        do { try await action(); await refresh() } catch { self.error = error.localizedDescription }
    }
    func scheduleNotifications() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        let requests = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix("reef-") })
        for reminder in reminders where !reminder.isComplete && reminder.dueDate > .now {
            let content = UNMutableNotificationContent()
            content.title = "Reef Log"
            content.body = reminder.title
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.dueDate.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "reef-\(reminder.id)", content: content, trigger: trigger))
        }
    }
    func enableNotifications() async {
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]); await scheduleNotifications() }
        catch { self.error = error.localizedDescription }
    }
}

struct ReefRootView: View {
    @State private var store = ReefStore()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TabView {
            NavigationStack { OverviewView(store: store) }.tabItem { Label("Overview", systemImage: "water.waves") }
            NavigationStack { HistoryView(store: store) }.tabItem { Label("History", systemImage: "chart.xyaxis.line") }
            NavigationStack { MaintenanceView(store: store) }.tabItem { Label("Maintenance", systemImage: "calendar.badge.clock") }
            NavigationStack { SettingsView(store: store) }.tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task { await store.refresh() }
        .onChange(of: phase) { _, value in if value == .active { Task { await store.refresh() } } }
        .alert("Reef Log", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct OverviewView: View {
    var store: ReefStore
    @State private var showTest = false
    @State private var showParameter = false
    var body: some View {
        List {
            Section {
                Button { showTest = true } label: { Label("New test session", systemImage: "plus.circle.fill") }
                    .disabled(store.metrics.isEmpty)
            }
            Section("Water parameters") {
                if store.metrics.isEmpty { ContentUnavailableView("No parameters", systemImage: "drop", description: Text("Add your first water parameter in Settings.")) }
                ForEach(store.metrics) { metric in
                    NavigationLink { MetricDetailView(store: store, metric: metric) } label: { MetricRow(metric: metric) }
                }
            }
            Section("Upcoming maintenance") {
                let pending = store.reminders.filter { !$0.isComplete }.prefix(3)
                if pending.isEmpty { Text("No upcoming reminders").foregroundStyle(.secondary) }
                ForEach(Array(pending)) { reminder in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reminder.title)
                        Text(reminder.dueDate, style: .date).font(.caption).foregroundStyle(reminder.dueDate < .now ? .red : .secondary)
                    }
                }
            }
        }
        .navigationTitle(store.tank.name)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } } } }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $showTest) { NavigationStack { TestSessionView(store: store) } }
    }
}

struct MetricRow: View {
    let metric: Metric
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(metric.name)
                if let date = metric.lastAt, let parsed = ReefDate.parse(date) { Text(parsed, style: .date).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let value = metric.lastValue {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(value.formatted()).font(.headline).monospacedDigit()
                    Text(metric.unit).font(.caption).foregroundStyle(.secondary)
                }
                if (metric.minValue.map { value < $0 } ?? false) || (metric.maxValue.map { value > $0 } ?? false) { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
            } else { Text("No readings").foregroundStyle(.secondary) }
        }
        .padding(.vertical, 3)
    }
}

struct TestSessionView: View {
    var store: ReefStore
    @Environment(\.dismiss) private var dismiss
    @State private var values: [Int: String] = [:]
    @State private var date = Date()
    @State private var saving = false
    var body: some View {
        Form {
            Section("Readings") {
                ForEach(store.metrics) { metric in
                    HStack {
                        Text(metric.name)
                        Spacer()
                        TextField("—", text: Binding(get: { values[metric.id] ?? "" }, set: { values[metric.id] = $0 }))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120)
                        Text(metric.unit).foregroundStyle(.secondary)
                    }
                }
            }
            Section { DatePicker("Recorded at", selection: $date) }
        }
        .navigationTitle("New Test")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(saving || !valid) }
        }
    }
    var valid: Bool { values.values.contains { Double($0) != nil } && values.values.allSatisfy { $0.isEmpty || Double($0) != nil } }
    func save() async {
        saving = true; defer { saving = false }
        let readings: [[String: Any]] = values.compactMap { key, value in guard let number = Double(value) else { return nil }; return ["metricId": key, "value": number] }
        do { try await ReefAPI.send("sessions", "POST", ["values": readings, "recordedAt": ReefDate.iso(date)]); await store.refresh(); dismiss() }
        catch { store.error = error.localizedDescription }
    }
}
