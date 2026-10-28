import Foundation

/// Everything the widget shows, written by the host app and read by the widget.
struct UsageSnapshot: Codable, Equatable {
    struct Limit: Codable, Equatable {
        /// Percent of the limit already used, 0...100.
        var usedPercent: Double
        var resetsAt: Date?

        var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
    }

    struct ScopedLimit: Codable, Equatable {
        var name: String
        var limit: Limit
    }

    struct TokenStats: Codable, Equatable {
        var input: Int = 0
        var output: Int = 0
        var cacheCreation: Int = 0
        var cacheRead: Int = 0
        var requests: Int = 0
    }

    enum Problem: String, Codable {
        case notLoggedIn
        case tokenExpired
        case network
    }

    /// When usage was last fetched successfully from the server.
    var fetchedAt: Date
    var session: Limit?
    var weekly: Limit?
    var scoped: [ScopedLimit] = []
    var tokens: TokenStats = .init()
    var plan: String?
    /// When the refresh token expires and `/login` is needed again.
    var loginExpiresAt: Date?
    /// Set when the last refresh attempt failed; older data is kept.
    var problem: Problem?

    static let placeholder = UsageSnapshot(
        fetchedAt: .now,
        session: .init(usedPercent: 3, resetsAt: .now.addingTimeInterval(2 * 3600 + 600)),
        weekly: .init(usedPercent: 2, resetsAt: .now.addingTimeInterval(3 * 86400)),
        scoped: [.init(name: "Fable", limit: .init(usedPercent: 0, resetsAt: nil))],
        tokens: .init(input: 144, output: 57_269, cacheCreation: 211_521, cacheRead: 10_342_879, requests: 68),
        plan: "Max 5x",
        loginExpiresAt: .now.addingTimeInterval(17 * 86400)
    )
}

enum SharedStore {
    static let appGroup = "89X7GT8Y93.com.sponomarenko.claudemonitor"
    static let widgetKind = "ClaudeMonitorWidget"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("snapshot.json")
    }

    static func load() -> UsageSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    static func save(_ snapshot: UsageSnapshot) throws {
        guard let url = fileURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
