import Foundation
import CryptoKit

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

    // MARK: Signing In

    /// Claude Code's own public client — the one every Claude token here is issued to and refreshed
    /// against.
    private static let claudeClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let codexClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let claudeTokenURL = "https://platform.claude.com/v1/oauth/token"
    /// Where Claude sends the code: its own page, which prints it for the reader to carry back.
    ///
    /// An app would rather be redirected straight back into itself, but the redirect addresses this
    /// client accepts are Claude's own page and a loopback port — not a scheme belonging to App
    /// Sales. The page is the half of that pair a phone can reach.
    private static let claudeRedirectURI = "https://platform.claude.com/oauth/code/callback"

    /// A sign-in part way through: the page to send the reader to, and the secrets that finish it.
    struct SignInRequest {
        let url: URL
        /// The PKCE secret proving the code came back to whoever asked for it.
        let verifier: String
        /// Round-trips through Claude, so a code pasted from some other sign-in is caught.
        let state: String
    }

    /// Starts Claude's OAuth sign-in — the only route to a token that can read usage.
    ///
    /// The long-lived token `claude setup-token` prints carries `user:inference` and nothing else,
    /// and the usage endpoint refuses it; only a full sign-in grants `user:profile`. Doing the sign-in
    /// here also gives App Sales a token family of its own, so refreshing one never rotates the
    /// terminal's out from under it.
    static func claudeSignInRequest() -> SignInRequest {
        let verifier = randomKey(bytes: 32)
        let state = randomKey(bytes: 16)

        var components = URLComponents(string: "https://claude.com/cai/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: claudeClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: claudeRedirectURI),
            // `user:profile` is what the usage endpoint reads; `user:inference` is the scope the
            // client always carries. Nothing here asks to spend the limits it reports.
            URLQueryItem(name: "scope", value: "user:profile user:inference"),
            URLQueryItem(name: "code_challenge", value: Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return SignInRequest(url: components?.url ?? url("https://claude.com"), verifier: verifier, state: state)
    }

    /// Finishes Claude's sign-in with what the reader brought back from that page.
    static func claudeSignIn(code pasted: String, request: SignInRequest) async throws -> AIUsageSignIn {
        guard let (code, state) = authorizationCode(in: pasted), state == nil || state == request.state else {
            throw AIUsageError.unreadableSignIn(.claude)
        }

        var tokenRequest = URLRequest(url: url(claudeTokenURL))
        tokenRequest.httpMethod = "POST"
        tokenRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        tokenRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": claudeRedirectURI,
            "client_id": claudeClientID,
            "code_verifier": request.verifier,
            "state": state ?? request.state,
        ])

        let json: [String: Any]
        do {
            json = try await send(tokenRequest, as: .claude)
        } catch AIUsageError.signInExpired {
            // A code is refused the same way a stale token is, but nothing has expired yet: it was
            // mistyped, or it was already spent on an earlier attempt.
            throw AIUsageError.assistant(String(localized: "That code did not work. Sign in again to get a new one."))
        }
        guard let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw AIUsageError.unreadableSignIn(.claude)
        }

        let signIn = AIUsageSignIn(
            assistant: .claude,
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            // A minute's grace, so a token cannot expire between the check and the request.
            expires: number(json["expires_in"]).map { .now.addingTimeInterval($0 - 60) },
            label: (json["account"] as? [String: Any])?["email_address"] as? String)
        return await claudeProfile(signIn)
    }

    /// Reads the code out of whatever was pasted: the `code#state` Claude's page prints, the whole
    /// callback address copied from the browser, or the code by itself.
    private static func authorizationCode(in pasted: String) -> (code: String, state: String?)? {
        let pasted = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pasted.isEmpty else { return nil }

        if pasted.contains("://"), let items = URLComponents(string: pasted)?.queryItems {
            guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { return nil }

            return (code, items.first(where: { $0.name == "state" })?.value)
        }

        let halves = pasted.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard let code = halves.first.map(String.init), !code.isEmpty else { return nil }

        return (code, halves.count > 1 ? String(halves[1]) : nil)
    }

    /// Who signed in and what they pay for — neither of which the token itself says, and neither of
    /// which is worth failing a sign-in over.
    private static func claudeProfile(_ signIn: AIUsageSignIn) async -> AIUsageSignIn {
        var request = URLRequest(url: url("https://api.anthropic.com/api/oauth/profile"))
        request.setValue("Bearer \(signIn.accessToken)", forHTTPHeaderField: "Authorization")
        guard let json = try? await send(request, as: .claude) else { return signIn }

        var signIn = signIn
        signIn.label = (json["account"] as? [String: Any])?["email"] as? String ?? signIn.label
        // `claude_pro` is the organization's type; `Pro` is the subscription a person recognizes.
        let organizationType = (json["organization"] as? [String: Any])?["organization_type"] as? String
        signIn.plan = AIUsageSignIn.planName(organizationType?.replacingOccurrences(of: "claude_", with: "")) ?? signIn.plan
        return signIn
    }

    private static func randomKey(bytes: Int) -> String {
        Data((0..<bytes).map { _ in UInt8.random(in: .min ... .max) }).base64URLEncoded
    }

    // MARK: Refreshing the Sign-In

    /// Swaps a refresh token for a working access token.
    ///
    /// The rotated refresh token that comes back replaces the saved one. Both assistants treat a
    /// reused refresh token as theft and revoke the whole family, which is why `AIAssistants` lets
    /// only one refresh per assistant be in flight at a time.
    static func refresh(_ signIn: AIUsageSignIn) async throws -> AIUsageSignIn {
        guard let refreshToken = signIn.refreshToken else { throw AIUsageError.signInExpired }

        var body: [String: Any] = ["grant_type": "refresh_token", "refresh_token": refreshToken]
        let endpoint: String
        switch signIn.assistant {
        case .claude:
            endpoint = claudeTokenURL
            body["client_id"] = claudeClientID
        case .codex:
            endpoint = "https://auth.openai.com/oauth/token"
            body["client_id"] = codexClientID
            body["scope"] = "openid profile email"
        }

        var request = URLRequest(url: url(endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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
        if let account = json["account"] as? [String: Any] {
            refreshed.label = account["email_address"] as? String ?? refreshed.label
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
