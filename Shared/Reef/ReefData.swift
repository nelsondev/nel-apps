import Foundation

struct Tank: Codable { let id: Int; var name: String }
struct Metric: Codable, Identifiable { let id: Int; var name: String; var unit: String; var minValue: Double?; var maxValue: Double?; var lastValue: Double?; var lastAt: String?
    enum CodingKeys: String, CodingKey { case id,name,unit; case minValue = "min_value", maxValue = "max_value", lastValue = "last_value", lastAt = "last_at" }
}
struct Reading: Codable, Identifiable { let id: Int; let metricId: Int; let value: Double; let note: String; let recordedAt: String
    enum CodingKeys: String, CodingKey { case id,value,note; case metricId = "metric_id", recordedAt = "recorded_at" }
}
struct Trend: Codable { let metricId: Int; let value: Double; let recordedAt: String
    enum CodingKeys: String, CodingKey { case value; case metricId = "metric_id", recordedAt = "recorded_at" }
}
struct ReefReminder: Codable, Identifiable { let id: Int; var title: String; var repeatDays: Int; var dueAt: String; var completedAt: String?
    enum CodingKeys: String, CodingKey { case id,title; case repeatDays = "repeat_days", dueAt = "due_at", completedAt = "completed_at" }
    var dueDate: Date { ReefDate.parse(dueAt) ?? .now }
    var isComplete: Bool { repeatDays == 0 && completedAt != nil }
}
enum ReefDate {
    static func parse(_ value: String) -> Date? { ISO8601DateFormatter().date(from: value) ?? ISO8601DateFormatter.fractional.date(from: value) }
    static func iso(_ value: Date) -> String { ISO8601DateFormatter().string(from: value) }
}
private extension ISO8601DateFormatter { static var fractional: ISO8601DateFormatter { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f } }
struct ReefSnapshot: Codable { let tankName: String; let metrics: [Metric]; let reminders: [ReefReminder] }
enum ReefCache {
    static let group = "group.lab.nel.reef"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
    static func save(_ snapshot: ReefSnapshot) { if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: "snapshot") } }
    static func read() -> ReefSnapshot? { guard let data = defaults.data(forKey: "snapshot") else { return nil }; return try? JSONDecoder().decode(ReefSnapshot.self, from: data) }
}
enum ReefAPI {
    // Change this URL to the HTTPS hostname of your existing Reef Log server.
    static let base = URL(string: "https://reef.home.lab")!
    static func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        var request = URLRequest(url: URL(string: "api/" + path, relativeTo: base.appendingPathComponent("/"))!.absoluteURL)
        request.httpMethod = method
        request.timeoutInterval = 20
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ReefError.message("Invalid server response") }
        guard (200...299).contains(response.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw ReefError.message(object?["error"] as? String ?? "Server error (\(response.statusCode))")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    static func get<T: Decodable>(_ path: String) async throws -> T { try await request(path) }
    static func send(_ path: String, _ method: String, _ body: [String: Any] = [:]) async throws { let _: APIResult = try await request(path, method: method, body: body) }
    static func delete(_ path: String) async throws { let _: APIResult = try await request(path, method: "DELETE") }
}
struct APIResult: Decodable { let ok: Bool?; let id: Int?; let completed: Int? }
enum ReefError: LocalizedError { case message(String); var errorDescription: String? { if case let .message(value) = self { return value }; return nil } }
