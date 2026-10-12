import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct API: Sendable {
    let base: URL
    init(port: Int) { base = URL(string: "http://127.0.0.1:\(port)")! }

    func url(_ path: String, query: [String: String] = [:]) -> URL {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    func data(_ path: String, method: String = "GET", query: [String: String] = [:], body: Data? = nil, contentType: String? = nil) async throws -> Data {
        var request = URLRequest(url: url(path, query: query), timeoutInterval: 120)
        request.httpMethod = method
        request.httpBody = body
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let (result, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Limit server diagnostics and never print submitted credentials.
            let detail = String(data: result, encoding: .utf8)?.prefix(600) ?? "No response"
            throw APIError(message: "Server returned \(code): \(detail)")
        }
        return result
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try JSONDecoder().decode(T.self, from: await data("api/v1/" + path, query: query))
    }

    @discardableResult
    func action(_ path: String, method: String = "GET", query: [String: String] = [:], form: [String: String]? = nil, json: [String: Any]? = nil) async throws -> Data {
        var body: Data? = nil
        var contentType: String? = nil
        if let form {
            var c = URLComponents()
            c.queryItems = form.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            body = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
            contentType = "application/x-www-form-urlencoded"
        }
        if let json { body = try JSONSerialization.data(withJSONObject: json); contentType = "application/json" }
        return try await data("api/v1/" + path, method: method, query: query, body: body, contentType: contentType)
    }

    func graphql(_ query: String, variables: [String: Any] = [:]) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let result = try await data("api/graphql", method: "POST", body: body, contentType: "application/json")
        guard let object = try JSONSerialization.jsonObject(with: result) as? [String: Any] else { throw APIError(message: "Invalid server response") }
        if let errors = object["errors"] as? [[String: Any]], !errors.isEmpty {
            throw APIError(message: errors.compactMap { $0["message"] as? String }.joined(separator: "\n"))
        }
        return object["data"] as? [String: Any] ?? [:]
    }
}
