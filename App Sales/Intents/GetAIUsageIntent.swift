import AppIntents
import SwiftUI

/// "How much Claude have I got left?" — one assistant's two rate limit windows, without opening a
/// window, placing a widget, or looking up at the menu bar.
///
/// The question this answers is the one a reader asks while they are already in a terminal, which
/// is exactly where Siri and `shortcuts run` reach and the rest of the AI usage surfaces do not.
struct GetAIUsageIntent: AppIntent {

    static var title: LocalizedStringResource = "Get AI Usage"
    static var description = IntentDescription(
        "Reports how much of a coding assistant's five-hour and weekly limits are spent.",
        categoryName: "AI Usage",
        resultValueName: "Usage")

    /// Unset means whichever connected assistant is closest to running out — the one whose limit is
    /// about to matter, the same choice the narrow widget families make.
    @Parameter(title: "Assistant")
    var assistant: AIAssistant?

    static var parameterSummary: some ParameterSummary {
        Summary("Get AI usage for \(\.$assistant)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<AIUsageEntity> & ProvidesDialog & ShowsSnippetView {
        let usage = try await AIUsageIntentData.usage(for: assistant)

        return .result(
            value: AIUsageEntity(usage),
            dialog: dialog(for: usage),
            view: AIUsageSnippet(usage: usage))
    }

    /// A sentence Siri can read out on its own, phrased the way the reader asked for elsewhere —
    /// "34% used" or "66% left", whichever `AIUsageDisplay` is set to.
    private func dialog(for usage: AIUsage) -> IntentDialog {
        let display = AIUsageDisplay.current
        let name = usage.assistant.name

        switch (usage.fiveHour, usage.week) {
        case (let fiveHour?, let week?):
            return IntentDialog("\(name): \(display.summary(of: fiveHour)) of the five-hour window, \(display.summary(of: week)) of the week.")
        case (let fiveHour?, nil):
            return IntentDialog("\(name): \(display.summary(of: fiveHour)) of the five-hour window.")
        case (nil, let week?):
            return IntentDialog("\(name): \(display.summary(of: week)) of the week.")
        case (nil, nil):
            return IntentDialog("\(name) did not report a limit.")
        }
    }
}

/// One assistant's reading, so a shortcut can branch on a single figure instead of parsing a
/// sentence — "if Five Hours Left is under 0.2, stop starting jobs".
///
/// Every fraction here is `0...1`, the unit `AIUsageLimit.used` is in and the one
/// `.formatted(.percent)` expects, rather than a second scale that would have to be kept in step.
struct AIUsageEntity: AppEntity {

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "AI Usage" }
    static var defaultQuery = AIUsageQuery()

    let assistant: AIAssistant

    /// The assistant is the identity: there is one reading per assistant, replaced rather than
    /// accumulated, so a saved shortcut referencing "Claude" still finds today's figures.
    var id: String { assistant.rawValue }

    @Property(title: "Assistant")
    var name: String

    @Property(title: "Plan")
    var plan: String?

    @Property(title: "Five Hours Used")
    var fiveHourUsed: Double?

    @Property(title: "Five Hours Left")
    var fiveHourLeft: Double?

    @Property(title: "Five Hours Reset")
    var fiveHourResetsAt: Date?

    @Property(title: "Week Used")
    var weekUsed: Double?

    @Property(title: "Week Left")
    var weekLeft: Double?

    @Property(title: "Week Reset")
    var weekResetsAt: Date?

    @Property(title: "Updated")
    var updated: Date

    init(_ usage: AIUsage) {
        self.assistant = usage.assistant
        self.name = usage.assistant.name
        self.plan = usage.plan
        self.fiveHourUsed = usage.fiveHour?.used
        self.fiveHourLeft = usage.fiveHour.map { 1 - $0.used }
        self.fiveHourResetsAt = usage.fiveHour?.resetsAt
        self.weekUsed = usage.week?.used
        self.weekLeft = usage.week.map { 1 - $0.used }
        self.weekResetsAt = usage.week?.resetsAt
        self.updated = usage.fetched
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: subtitle,
            image: .init(systemName: assistant.systemImage))
    }

    private var subtitle: LocalizedStringResource? {
        guard let used = fiveHourUsed else { return nil }

        let display = AIUsageDisplay.current
        return "\(display.summary(of: AIUsageLimit(used: used, resetsAt: fiveHourResetsAt))) of the five-hour window"
    }
}

/// Resolves readings for saved shortcuts, out of the shared cache alone.
///
/// Deliberately never fetches: a usage fetch can rotate a refresh token, and a refresh token used
/// twice gets its family revoked — which would sign the reader's own terminal out. Filling a picker
/// is not worth that, and the intent itself fetches when it is actually run.
struct AIUsageQuery: EntityQuery {

    func entities(for identifiers: [AIUsageEntity.ID]) async throws -> [AIUsageEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AIUsageEntity] {
        AIUsageCache.all().map(AIUsageEntity.init)
    }
}

/// The one place an AI usage intent resolves an assistant and reads its limits.
///
/// Everything goes through `AIAssistants.shared.usage(for:)`, which prefers the App Group cache the
/// app, both widget extensions, and the menu bar extra already share — so an intent is not a fifth
/// process spending a fetch of its own.
enum AIUsageIntentData {

    /// The requested assistant's reading, or — with none requested — whichever connected assistant
    /// is closest to running out.
    static func usage(for requested: AIAssistant?) async throws -> AIUsage {
        let readings = try await all(requested)

        guard let tightest = readings.max(by: { ($0.tightestLimit?.used ?? 0) < ($1.tightestLimit?.used ?? 0) }) else {
            throw AIUsageError.notSignedIn
        }
        return tightest
    }

    /// One assistant at a time. Two at once could each find their sign-in expired and each refresh
    /// it, and a refresh token used twice gets its family revoked.
    private static func all(_ requested: AIAssistant?) async throws -> [AIUsage] {
        let connected = await AIAssistants.shared.connected
        let wanted = requested.map { connected.contains($0) ? [$0] : [] } ?? connected

        guard !wanted.isEmpty else { throw AIUsageError.notSignedIn }

        var readings: [AIUsage] = []
        var failure: Error?

        for assistant in wanted {
            do {
                readings.append(try await AIAssistants.shared.usage(for: assistant))
            } catch {
                // One assistant failing should not blank the other, or throw away the last reading:
                // stale figures still say roughly where the week stands.
                if let cached = AIUsageCache.usage(for: assistant) {
                    readings.append(cached)
                } else if failure == nil {
                    failure = error
                }
            }
        }

        if readings.isEmpty, let failure {
            throw failure
        }
        return readings
    }
}

/// Lets an `AIUsageError` surface in Shortcuts with the same wording the app shows, as `APIError`
/// already does for the sales intents.
extension AIUsageError: CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "\(errorDescription ?? String(localized: "An unknown error occurred."))"
    }
}

/// The card Siri and Shortcuts show: the same block the home screen widget and the Mac's menu bar
/// extra draw, so the answer looks like the app rather than like a second rendering of it.
struct AIUsageSnippet: View {

    let usage: AIUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AIUsageColumn(usage: usage, display: .current)

            Text("Updated \(usage.fetched, format: .relative(presentation: .numeric))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

#Preview {
    AIUsageSnippet(usage: AIUsage.examples[0])
}
