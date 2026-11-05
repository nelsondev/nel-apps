import SwiftUI
import Charts

struct HistoryView: View {
    var store: ReefStore
    var body: some View {
        List {
            Section("Parameter history") {
                ForEach(store.metrics) { metric in
                    NavigationLink { MetricDetailView(store: store, metric: metric) } label: { MetricRow(metric: metric) }
                }
            }
        }
        .navigationTitle("History")
        .refreshable { await store.refresh() }
    }
}

struct MetricDetailView: View {
    var store: ReefStore
    let metric: Metric
    @State private var readings: [Reading] = []
    var body: some View {
        List {
            Section("Trend") {
                let values = store.trends.filter { $0.metricId == metric.id }.suffix(120)
                if values.isEmpty { Text("No readings yet").foregroundStyle(.secondary) }
                else {
                    Chart(Array(values.enumerated()), id: \.offset) { point in
                        if let date = ReefDate.parse(point.element.recordedAt) {
                            LineMark(x: .value("Date", date), y: .value("Value", point.element.value))
                            PointMark(x: .value("Date", date), y: .value("Value", point.element.value)).symbolSize(12)
                        }
                    }
                    .frame(height: 210)
                }
                if metric.minValue != nil || metric.maxValue != nil {
                    Text("Preferred range: \(metric.minValue.map { $0.formatted() } ?? "—") – \(metric.maxValue.map { $0.formatted() } ?? "—") \(metric.unit)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Readings") {
                ForEach(readings) { reading in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(reading.value.formatted() + " " + metric.unit)
                            if let date = ReefDate.parse(reading.recordedAt) { Text(date, style: .date).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Delete", systemImage: "trash", role: .destructive) { Task { await store.execute { try await ReefAPI.delete("entries/\(reading.id)") }; await load() } }
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .navigationTitle(metric.name)
        .task { await load() }
        .refreshable { await load() }
    }
    func load() async { do { readings = try await ReefAPI.get("entries?metricId=\(metric.id)") } catch { store.error = error.localizedDescription } }
}

struct MaintenanceView: View {
    var store: ReefStore
    @State private var editing: ReefReminder?
    @State private var showNew = false
    var body: some View {
        List {
            Section {
                Button("Enable reminders", systemImage: "bell.badge") { Task { await store.enableNotifications() } }
            } footer: { Text("Notifications are scheduled locally when this app synchronizes. Open the app after changing reminders on another device.") }
            Section("Scheduled") {
                if store.reminders.isEmpty { Text("No reminders").foregroundStyle(.secondary) }
                ForEach(store.reminders) { reminder in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reminder.title)
                            Text(reminder.isComplete ? "Completed" : reminder.dueDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                            if reminder.repeatDays > 0 { Text("Every \(reminder.repeatDays) days").font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Edit", systemImage: "pencil") { editing = reminder }.labelStyle(.iconOnly)
                        if !reminder.isComplete {
                            Button("Done", systemImage: "checkmark.circle") { Task { await store.execute { try await ReefAPI.send("reminders/\(reminder.id)/complete", "POST") } } }.labelStyle(.iconOnly)
                        }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { Task { await store.execute { try await ReefAPI.delete("reminders/\(reminder.id)") } } } }
                }
            }
        }
        .navigationTitle("Maintenance")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Add", systemImage: "plus") { showNew = true } } }
        .sheet(isPresented: $showNew) { NavigationStack { ReminderEditor(store: store, reminder: nil) } }
        .sheet(item: $editing) { reminder in NavigationStack { ReminderEditor(store: store, reminder: reminder) } }
        .refreshable { await store.refresh() }
    }
}

struct ReminderEditor: View {
    var store: ReefStore
    let reminder: ReefReminder?
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var days = 7
    @State private var due = Date().addingTimeInterval(86400)
    @State private var saving = false
    var body: some View {
        Form {
            TextField("Task", text: $title)
            DatePicker("Next due", selection: $due)
            Picker("Repeat", selection: $days) {
                Text("One time").tag(0); Text("Daily").tag(1); Text("Weekly").tag(7); Text("Every 2 weeks").tag(14); Text("Every 30 days").tag(30)
            }
        }
        .navigationTitle(reminder == nil ? "New Reminder" : "Edit Reminder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving) }
        }
        .onAppear { if let reminder { title = reminder.title; days = reminder.repeatDays; due = reminder.dueDate } }
    }
    func save() async {
        saving = true; defer { saving = false }
        do {
            try await ReefAPI.send(reminder.map { "reminders/\($0.id)" } ?? "reminders", reminder == nil ? "POST" : "PATCH", ["title": title, "repeatDays": days, "dueAt": ReefDate.iso(due)])
            await store.refresh(); dismiss()
        } catch { store.error = error.localizedDescription }
    }
}

struct SettingsView: View {
    var store: ReefStore
    @State private var showAdd = false
    @State private var editing: Metric?
    @State private var tankName = ""
    var body: some View {
        Form {
            Section("Aquarium") {
                TextField("Name", text: $tankName)
                Button("Save aquarium name") { Task { await store.execute { try await ReefAPI.send("tank", "PATCH", ["name": tankName]) } } }
                    .disabled(tankName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section("Water parameters") {
                ForEach(store.metrics) { metric in
                    Button { editing = metric } label: { HStack { Text(metric.name); Spacer(); Text(metric.unit).foregroundStyle(.secondary); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) } }
                        .foregroundStyle(.primary)
                        .swipeActions { Button("Delete", role: .destructive) { Task { await store.execute { try await ReefAPI.delete("metrics/\(metric.id)") } } } }
                }
                Button("Add parameter", systemImage: "plus") { showAdd = true }
            }
            Section("Server") {
                LabeledContent("Address", value: ReefAPI.base.absoluteString)
                Text("Your existing Reef Log server remains the source of truth. Set the address in Shared/ReefData.swift before building.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .onAppear { tankName = store.tank.name }
        .sheet(isPresented: $showAdd) { NavigationStack { ParameterEditor(store: store, metric: nil) } }
        .sheet(item: $editing) { metric in NavigationStack { ParameterEditor(store: store, metric: metric) } }
    }
}

struct ParameterEditor: View {
    var store: ReefStore
    let metric: Metric?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var unit = ""
    @State private var minimum = ""
    @State private var maximum = ""
    var body: some View {
        Form {
            Section("Parameter") { TextField("Name", text: $name); TextField("Unit", text: $unit) }
            Section("Preferred range") {
                TextField("Minimum (optional)", text: $minimum).keyboardType(.decimalPad)
                TextField("Maximum (optional)", text: $maximum).keyboardType(.decimalPad)
            }
        }
        .navigationTitle(metric == nil ? "Add Parameter" : "Edit Parameter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .onAppear { if let metric { name = metric.name; unit = metric.unit; minimum = metric.minValue.map { String($0) } ?? ""; maximum = metric.maxValue.map { String($0) } ?? "" } }
    }
    func save() async {
        let min: Any = minimum.isEmpty ? NSNull() : (Double(minimum).map { $0 as Any } ?? NSNull())
        let max: Any = maximum.isEmpty ? NSNull() : (Double(maximum).map { $0 as Any } ?? NSNull())
        do {
            try await ReefAPI.send(metric.map { "metrics/\($0.id)" } ?? "metrics", metric == nil ? "POST" : "PATCH", ["name": name, "unit": unit, "minValue": min, "maxValue": max])
            await store.refresh(); dismiss()
        } catch { store.error = error.localizedDescription }
    }
}
