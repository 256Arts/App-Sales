import Foundation

/// The two assistants' usage endpoints, and the token refresh that keeps reaching them.
///
/// Both answer the same two questions — how much of the five-hour window and of the week is gone —
/// so both land on `AIUsage`. Neither is a documented, versioned API; both are the endpoint the
/// assistant's own command line tool calls, so every field is read defensively and a shape that has
/// moved on leaves a window empty rather than failing the whole fetch.
enum AIUsageAPI {

    static func usage(_ signIn: AIUsageSignIn) async throws -> AIUsage {
        switch signIn.assistant {
        case .claude: try await claudeUsage(signIn)
        case .codex: try await codexUsage(signIn)
        }
    }

    // MARK: Claude

    private static func claudeUsage(_ signIn: AIUsageSignIn) async throws -> AIUsage {
        var request = URLRequest(url: url("https://api.anthropic.com/api/oauth/usage"))
        request.setValue("Bearer \(signIn.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let json = try await send(request, as: .claude)

        var fiveHour = claudeLimit(json["five_hour"], percentKey: "utilization")
        var week = claudeLimit(json["seven_day"], percentKey: "utilization")
        // Newer responses null out the named windows and report every limit in `limits` instead, so
        // an entry there wins over whatever the named window said.
        for entry in json["limits"] as? [[String: Any]] ?? [] {
            switch entry["kind"] as? String {
            case "session": fiveHour = claudeLimit(entry, percentKey: "percent") ?? fiveHour
            case "weekly_all": week = claudeLimit(entry, percentKey: "percent") ?? week
            default: continue
            }
        }

        return AIUsage(assistant: .claude, plan: signIn.plan, fiveHour: fiveHour, week: week, fetched: .now)
    }

    /// Both of Claude's shapes report a percentage `0...100` and an ISO 8601 reset time.
    private static func claudeLimit(_ object: Any?, percentKey: String) -> AIUsageLimit? {
        guard let object = object as? [String: Any], let percent = number(object[percentKey]) else { return nil }

        return AIUsageLimit(used: percent / 100, resetsAt: (object["resets_at"] as? String).flatMap(date(fromISO8601:)))
    }

    // MARK: Codex

    private static func codexUsage(_ signIn: AIUsageSignIn) async throws -> AIUsage {
        var request = URLRequest(url: url("https://chatgpt.com/backend-api/wham/usage"))
        request.setValue("Bearer \(signIn.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = signIn.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let json = try await send(request, as: .codex)
        let rateLimit = json["rate_limit"] as? [String: Any] ?? [:]
        let windows = ["primary_window", "secondary_window"].compactMap { rateLimit[$0] as? [String: Any] }
        let (fiveHour, week) = codexWindows(windows)

        return AIUsage(
            assistant: .codex,
            plan: AIUsageSignIn.planName(json["plan_type"] as? String) ?? signIn.plan,
            fiveHour: fiveHour,
            week: week,
            fetched: .now)
    }

    /// Codex labels its two windows "primary" and "secondary" and does not promise which is which,
    /// so their lengths decide. Where a length is missing from both, the order they arrive in is all
    /// there is to go on.
    private static func codexWindows(_ windows: [[String: Any]]) -> (fiveHour: AIUsageLimit?, week: AIUsageLimit?) {
        guard windows.contains(where: { number($0["limit_window_seconds"]) != nil }) else {
            return (codexLimit(windows.first), codexLimit(windows.dropFirst().first))
        }

        let aDay: Double = 24 * 60 * 60
        return (
            codexLimit(windows.first { (number($0["limit_window_seconds"]) ?? 0) < aDay }),
            codexLimit(windows.first { (number($0["limit_window_seconds"]) ?? 0) >= aDay })
        )
    }

    private static func codexLimit(_ window: [String: Any]?) -> AIUsageLimit? {
        guard let window, let percent = number(window["used_percent"]) else { return nil }

        return AIUsageLimit(used: percent / 100, resetsAt: number(window["reset_at"]).map(Date.init(timeIntervalSince1970:)))
    }

    // MARK: Refreshing the Sign-In

    /// Swaps a refresh token for a working access token.
    ///
    /// The rotated refresh token that comes back replaces the saved one. Both assistants treat a
    /// reused refresh token as theft and revoke the whole family, which is why `AIAssistants` lets
    /// only one refresh per assistant be in flight at a time.
    static func refresh(_ signIn: AIUsageSignIn) async throws -> AIUsageSignIn {
        guard let refreshToken = signIn.refreshToken else { throw AIUsageError.signInExpired }

        var request: URLRequest
        switch signIn.assistant {
        case .claude:
            // Claude Code's own public client — the one that issued the token being refreshed.
            request = URLRequest(url: url("https://platform.claude.com/v1/oauth/token"))
            var components = URLComponents()
            components.queryItems = [
                URLQueryItem(name: "grant_type", value: "refresh_token"),
                URLQueryItem(name: "refresh_token", value: refreshToken),
                URLQueryItem(name: "client_id", value: "9d1c250a-e61b-44d9-88ed-5944d1962f5e"),
            ]
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        case .codex:
            request = URLRequest(url: url("https://auth.openai.com/oauth/token"))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "scope": "openid profile email",
            ])
        }
        request.httpMethod = "POST"

        let json = try await send(request, as: signIn.assistant)
        var refreshed = signIn
        refreshed.accessToken = json["access_token"] as? String ?? signIn.accessToken
        refreshed.refreshToken = json["refresh_token"] as? String ?? refreshToken
        if let seconds = number(json["expires_in"]) {
            // A minute's grace, so a token cannot expire between the check and the request.
            refreshed.expires = .now.addingTimeInterval(seconds - 60)
        } else {
            refreshed.expires = AIUsageSignIn.expiry(ofJWT: refreshed.accessToken)
        }
        if let idToken = json["id_token"] as? String {
            refreshed.label = AIUsageSignIn.email(ofJWT: idToken) ?? refreshed.label
        }
        return refreshed
    }

    // MARK: Sending

    private static func send(_ request: URLRequest, as assistant: AIAssistant) async throws -> [String: Any] {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Usage is the one thing here that is stale the moment it is cached.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 || isRejectedGrant(data) {
            throw AIUsageError.signInExpired
        }
        guard status == 200, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AIUsageError.assistant(String(localized: "\(assistant.name) could not be reached."))
        }
        return json
    }

    /// A refused refresh answers `400`, not `401`, and names the reason in the body.
    private static func isRejectedGrant(_ data: Data) -> Bool {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }

        let code = (json["error"] as? String) ?? ((json["error"] as? [String: Any])?["code"] as? String) ?? ""
        return ["invalid_grant", "refresh_token_expired", "refresh_token_reused", "refresh_token_invalidated"].contains(code)
    }

    // MARK: Reading Loose Values

    private static func url(_ string: String) -> URL {
        URL(string: string) ?? URL(filePath: "/")
    }

    /// The assistants are inconsistent about writing a percentage as `9`, `9.0`, or `"9"`.
    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static let fractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let wholeSecondsFormatter = ISO8601DateFormatter()

    private static func date(fromISO8601 string: String) -> Date? {
        fractionalSecondsFormatter.date(from: string) ?? wholeSecondsFormatter.date(from: string)
    }
}
