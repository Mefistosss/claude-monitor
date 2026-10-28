import Foundation

/// Reads Claude Code's OAuth credentials, queries the usage endpoint and
/// sums token counts from local Claude Code logs.
enum UsageFetcher {
    struct Credentials {
        var accessToken: String
        var expiresAt: Date?
        var refreshExpiresAt: Date?
        var plan: String?
    }

    enum FetchError: Error {
        case notLoggedIn
        case tokenExpired
        case network
    }

    /// Builds a fresh snapshot. On failure the previous snapshot's usage is kept
    /// and `problem` is set, so the widget can show stale data with a warning.
    static func refresh(previous: UsageSnapshot?) async -> UsageSnapshot {
        let tokens = LogScanner.lastHours(5)
        let creds = try? readCredentials()

        var snapshot = previous ?? UsageSnapshot(fetchedAt: .distantPast)
        snapshot.tokens = tokens
        if let creds {
            snapshot.plan = creds.plan
            snapshot.loginExpiresAt = creds.refreshExpiresAt
        }

        do {
            guard let creds else { throw FetchError.notLoggedIn }
            if let exp = creds.expiresAt, exp < .now { throw FetchError.tokenExpired }
            let usage = try await fetchUsage(token: creds.accessToken)
            snapshot.session = usage.session
            snapshot.weekly = usage.weekly
            snapshot.scoped = usage.scoped
            snapshot.fetchedAt = .now
            snapshot.problem = nil
        } catch FetchError.notLoggedIn {
            snapshot.problem = .notLoggedIn
        } catch FetchError.tokenExpired {
            snapshot.problem = .tokenExpired
        } catch {
            snapshot.problem = .network
        }
        return snapshot
    }

    // MARK: - Credentials

    /// Uses `/usr/bin/security`, which Claude Code itself uses to store the item,
    /// so reading it does not trigger a Keychain access prompt.
    static func readCredentials() throws -> Credentials {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw FetchError.notLoggedIn }

        func date(_ key: String) -> Date? {
            (oauth[key] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        }
        return Credentials(
            accessToken: token,
            expiresAt: date("expiresAt"),
            refreshExpiresAt: date("refreshTokenExpiresAt"),
            plan: planName(type: oauth["subscriptionType"] as? String, tier: oauth["rateLimitTier"] as? String)
        )
    }

    /// "max" + "default_claude_max_5x" -> "Max 5x"
    static func planName(type: String?, tier: String?) -> String? {
        guard let type, !type.isEmpty else { return nil }
        var name = type.prefix(1).uppercased() + type.dropFirst()
        if let multiplier = tier?.split(separator: "_").last, multiplier.hasSuffix("x"), multiplier.dropLast().allSatisfy(\.isNumber) {
            name += " \(multiplier)"
        }
        return name
    }

    // MARK: - Usage endpoint

    private struct UsageResponse: Decodable {
        struct Window: Decodable {
            var utilization: Double?
            var resets_at: String?
        }
        struct LimitEntry: Decodable {
            struct Scope: Decodable {
                struct Model: Decodable { var display_name: String? }
                var model: Model?
            }
            var kind: String
            var percent: Double?
            var resets_at: String?
            var scope: Scope?
        }
        var five_hour: Window?
        var seven_day: Window?
        var limits: [LimitEntry]?
    }

    private static func fetchUsage(token: String) async throws -> (session: UsageSnapshot.Limit?, weekly: UsageSnapshot.Limit?, scoped: [UsageSnapshot.ScopedLimit]) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw FetchError.tokenExpired }
        guard status == 200 else { throw FetchError.network }
        let usage = try JSONDecoder().decode(UsageResponse.self, from: data)

        func limit(_ percent: Double?, _ resets: String?) -> UsageSnapshot.Limit? {
            percent.map { .init(usedPercent: $0, resetsAt: parseDate(resets)) }
        }

        var session = limit(usage.five_hour?.utilization, usage.five_hour?.resets_at)
        var weekly = limit(usage.seven_day?.utilization, usage.seven_day?.resets_at)
        var scoped: [UsageSnapshot.ScopedLimit] = []
        for entry in usage.limits ?? [] {
            switch entry.kind {
            case "session":
                session = limit(entry.percent, entry.resets_at) ?? session
            case "weekly_all":
                weekly = limit(entry.percent, entry.resets_at) ?? weekly
            case "weekly_scoped":
                if let name = entry.scope?.model?.display_name, let l = limit(entry.percent, entry.resets_at) {
                    scoped.append(.init(name: name, limit: l))
                }
            default:
                break
            }
        }
        return (session, weekly, scoped)
    }

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
