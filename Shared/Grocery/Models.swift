import Foundation

struct GroceryItem: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

enum GroceryConfig {
    static let server = URL(string: "https://grocery.home.lab")!
    static let cacheKey = "grocery.cached.items"
    static let sharedGroup = "group.lab.nel.grocery"
}

struct GroceryAPI {
    struct APIError: LocalizedError {
        let statusCode: Int
        var errorDescription: String? { statusCode == 409 ? "Item already exists." : "Server returned HTTP \(statusCode)." }
    }
    static func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: String]? = nil) async throws -> T {
        var request = URLRequest(url: GroceryConfig.server.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 15
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw APIError(statusCode: http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }
    static func list() async throws -> [GroceryItem] { try await request("/api/groceries") }
    static func add(_ name: String) async throws { let _: GroceryItem = try await request("/api/groceries", method: "POST", body: ["name": name]) }
    static func buy(_ id: Int) async throws { let _: GroceryItem = try await request("/api/groceries/\(id)/buy", method: "PATCH") }
    static func completeAll() async throws { let _: Completed = try await request("/api/groceries/complete-all", method: "POST") }
    static func delete(_ id: Int) async throws {
        var request = URLRequest(url: GroceryConfig.server.appending(path: "/api/groceries/\(id)"))
        request.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }
    struct Completed: Decodable { let completed: Int }
}

enum GroceryCache {
    static var defaults: UserDefaults { UserDefaults(suiteName: GroceryConfig.sharedGroup) ?? .standard }
    static func read() -> [GroceryItem] { guard let data = defaults.data(forKey: GroceryConfig.cacheKey) else { return [] }; return (try? JSONDecoder().decode([GroceryItem].self, from: data)) ?? [] }
    static func save(_ items: [GroceryItem]) { defaults.set(try? JSONEncoder().encode(items), forKey: GroceryConfig.cacheKey) }
}
