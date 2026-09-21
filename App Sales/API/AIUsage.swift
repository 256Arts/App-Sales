import Foundation
import AppIntents

/// A coding assistant whose rate limits App Sales can show beside the day's sales.
///
/// Both of these are billed by a subscription rather than per call, so the number that matters is
/// not a bill — it is how much of the current window is left before the assistant stops answering.
enum AIAssistant: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: String(localized: "Claude")
        case .codex: String(localized: "Codex")
        }
    }

    var systemImage: String {
        switch self {
        case .claude: "asterisk"
        case .codex: "seal"
        }
    }

    /// The terminal command that prints a sign-in to paste in — `nil` for an assistant App Sales can
    /// sign into itself.
    ///
    /// Claude has an OAuth sign-in the app can drive, which works the same on a phone as on a Mac
    /// and asks the terminal for nothing. Codex's tokens only come out of its own command, so its
    /// sign-in is a copy of the file the CLI keeps.
    var signInCommand: String? {
        switch self {
        case .claude: nil
        case .codex: "cat ~/.codex/auth.json"
        }
    }

    /// The file the terminal keeps this assistant's sign-in in, under the home folder — `nil` for
    /// an assistant that does not keep one.
    ///
    /// Claude Code puts its sign-in in the login Keychain rather than on disk, in an item only it
    /// can open, so there is no file to offer and `signInCommand` is the whole story. Only the Mac's
    /// sign-in sheet reads this, and only to point the file picker somewhere useful: a sandboxed app
    /// cannot reach the path until the reader hands it the file.
    var credentialsFile: String? {
        switch self {
        case .claude: nil
        case .codex: ".codex/auth.json"
        }
    }
}

extension AIAssistant: AppEnum {

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Assistant" }

    /// Spelled out rather than built from `name`, because App Intents reads these at build time to
    /// compile the widget configuration's picker.
    static var caseDisplayRepresentations: [AIAssistant: DisplayRepresentation] {
        [
            .claude: DisplayRepresentation(title: "Claude", image: .init(systemName: "asterisk")),
            .codex: DisplayRepresentation(title: "Codex", image: .init(systemName: "seal")),
        ]
    }
}

/// How much of one rate limit window has been spent, and when it empties again.
struct AIUsageLimit: Codable, Hashable, Sendable {
    /// `0...1`, and past `1` only where an assistant reports going over.
    let used: Double
    /// `nil` where the assistant does not say — a window nobody has entered yet has no reset time.
    let resetsAt: Date?
}

/// One assistant's limits right now.
///
/// Both assistants meter the same two windows — a rolling five hours and a rolling week — so both
/// land here rather than in a per-assistant shape.
struct AIUsage: Codable, Hashable, Identifiable, Sendable {
    let assistant: AIAssistant
    /// The subscription the limits belong to, where the assistant names it.
    let plan: String?
    let fiveHour: AIUsageLimit?
    let week: AIUsageLimit?
    let fetched: Date

    var id: AIAssistant { assistant }
}

enum AIUsageError: LocalizedError {
    case notSignedIn
    /// The saved sign-in was refused: expired, revoked, or signed out somewhere else.
    case signInExpired
    /// What was pasted or picked is not a sign-in this assistant issued.
    case unreadableSignIn(AIAssistant)
    case assistant(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            String(localized: "You are not connected to this assistant.")
        case .signInExpired:
            String(localized: "The sign-in has expired. Sign in to the assistant again.")
        case .unreadableSignIn(let assistant):
            String(localized: "That is not a \(assistant.name) sign-in.")
        case .assistant(let message):
            message
        }
    }
}

extension AIUsage {

    /// Plausible figures for previews and App Store screenshots.
    ///
    /// Reset times are offsets from `.now`, the way `ACData.example` builds its entries, so the
    /// section reads the same whichever day a run happens on.
    static let examples: [AIUsage] = [
        AIUsage(
            assistant: .claude,
            plan: "Max",
            fiveHour: AIUsageLimit(used: 0.34, resetsAt: .now.addingTimeInterval(2 * 60 * 60)),
            week: AIUsageLimit(used: 0.61, resetsAt: .now.addingTimeInterval(3 * 24 * 60 * 60)),
            fetched: .now),
        AIUsage(
            assistant: .codex,
            plan: "Plus",
            fiveHour: AIUsageLimit(used: 0.08, resetsAt: .now.addingTimeInterval(4 * 60 * 60)),
            week: AIUsageLimit(used: 0.45, resetsAt: .now.addingTimeInterval(5 * 24 * 60 * 60)),
            fetched: .now),
    ]
}
