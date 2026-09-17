import Foundation

/// One assistant's saved sign-in: enough to ask it for usage, and to keep asking after the token it
/// arrived with has expired.
///
/// Neither assistant offers a web sign-in an app can drive — both hand their tokens out through a
/// command line tool — so App Sales takes a copy of one instead, pasted or read from the file the
/// terminal keeps it in. The copy is App Sales' own: refreshing it never writes back to the
/// terminal's file.
struct AIUsageSignIn: Codable, Hashable, Identifiable, Sendable {

    let assistant: AIAssistant
    var accessToken: String
    /// Absent on a long-lived token, which never needs one.
    var refreshToken: String?
    /// When `accessToken` stops working; `nil` for a long-lived token.
    var expires: Date?
    /// The workspace the Codex backend wants named alongside the token.
    var accountID: String?
    /// Who signed in, for the connected row to show.
    var label: String?
    /// The subscription, where the sign-in itself names it.
    var plan: String?

    var id: AIAssistant { assistant }

    var isExpired: Bool {
        guard let expires else { return false }

        return expires <= .now
    }

    init(assistant: AIAssistant, accessToken: String, refreshToken: String? = nil, expires: Date? = nil, accountID: String? = nil, label: String? = nil, plan: String? = nil) {
        self.assistant = assistant
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expires = expires
        self.accountID = accountID
        self.label = label
        self.plan = plan
    }
}

// MARK: Reading What Was Pasted

extension AIUsageSignIn {

    /// Reads whatever the reader pasted or picked: the assistant's credentials file, or a bare
    /// token. `nil` when it is neither.
    static func read(_ text: String, for assistant: AIAssistant) -> AIUsageSignIn? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        switch assistant {
        case .claude:
            return json.flatMap(claude) ?? bareClaudeToken(text)
        case .codex:
            return json.flatMap(codex) ?? bareCodexToken(text)
        }
    }

    /// The shape Claude Code keeps in its login Keychain item — which is where it puts the sign-in
    /// on a Mac, rather than in a file. Pasting a copy of that works, though `claude setup-token` is
    /// the path the sheet offers: taking the terminal's own sign-in means refreshing it here can
    /// rotate the terminal's out from under it.
    private static func claude(_ json: [String: Any]) -> AIUsageSignIn? {
        guard let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String, !accessToken.isEmpty else { return nil }

        return AIUsageSignIn(
            assistant: .claude,
            accessToken: accessToken,
            refreshToken: oauth["refreshToken"] as? String,
            // Milliseconds, unlike every other timestamp either assistant reports.
            expires: (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) },
            plan: planName(oauth["subscriptionType"] as? String))
    }

    /// What `claude setup-token` prints: a token with no refresh token, good for about a year.
    private static func bareClaudeToken(_ text: String) -> AIUsageSignIn? {
        guard text.hasPrefix("sk-ant-"), !text.contains(where: \.isWhitespace) else { return nil }

        return AIUsageSignIn(assistant: .claude, accessToken: text)
    }

    /// `~/.codex/auth.json`, in either of the two shapes the Codex CLI writes.
    private static func codex(_ json: [String: Any]) -> AIUsageSignIn? {
        guard let tokens = json["tokens"] as? [String: Any],
              let accessToken = string(tokens, "access_token", "accessToken") else {
            // An API key on its own, which the CLI writes when signed in that way.
            guard let key = json["OPENAI_API_KEY"] as? String, !key.isEmpty else { return nil }

            return AIUsageSignIn(assistant: .codex, accessToken: key)
        }

        let idToken = string(tokens, "id_token", "idToken")
        return AIUsageSignIn(
            assistant: .codex,
            accessToken: accessToken,
            refreshToken: string(tokens, "refresh_token", "refreshToken"),
            expires: expiry(ofJWT: accessToken),
            accountID: string(tokens, "account_id", "accountID") ?? accountID(ofJWT: accessToken),
            label: idToken.flatMap(email(ofJWT:)) ?? email(ofJWT: accessToken),
            plan: nil)
    }

    private static func bareCodexToken(_ text: String) -> AIUsageSignIn? {
        guard text.split(separator: ".").count == 3 else { return nil }

        return AIUsageSignIn(
            assistant: .codex,
            accessToken: text,
            expires: expiry(ofJWT: text),
            accountID: accountID(ofJWT: text),
            label: email(ofJWT: text))
    }

    /// `pro` and `free_workspace` are what the assistants write; `Pro` and `Free Workspace` are
    /// what a person calls them.
    static func planName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }

        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func string(_ json: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let value = json[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }
}

// MARK: Reading a Token's Own Claims

extension AIUsageSignIn {

    /// Codex's tokens are JWTs that say when they expire and who they belong to. Nothing here
    /// verifies a signature: these are read only to label and schedule a token the app already has.
    static func claims(ofJWT jwt: String) -> [String: Any]? {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while !base64.count.isMultiple(of: 4) {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64) else { return nil }

        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func expiry(ofJWT jwt: String) -> Date? {
        guard let expiry = claims(ofJWT: jwt)?["exp"] as? Double else { return nil }

        return Date(timeIntervalSince1970: expiry)
    }

    static func email(ofJWT jwt: String) -> String? {
        guard let email = claims(ofJWT: jwt)?["email"] as? String, !email.isEmpty else { return nil }

        return email
    }

    /// The workspace the token was issued for, which the Codex backend wants in a header of its own.
    static func accountID(ofJWT jwt: String) -> String? {
        guard let claims = claims(ofJWT: jwt) else { return nil }

        if let id = claims["chatgpt_account_id"] as? String, !id.isEmpty { return id }
        if let auth = claims["https://api.openai.com/auth"] as? [String: Any],
           let id = auth["chatgpt_account_id"] as? String, !id.isEmpty { return id }
        return nil
    }
}
