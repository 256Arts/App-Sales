import WidgetKit
import SwiftUI
import AppIntents

/// The AI usage widget, on every surface that has one: the home screen on iPhone, iPad, Mac, and
/// Vision, the iPhone's Lock Screen, and the watch face.
///
/// Both extensions build this file — it is the sales widget's `Widgets.swift` and `WatchWidgets.swift`
/// that differ, and only in which families they declare. Everything the figures need already exists
/// from part 1: the sign-ins reach here through the same iCloud-synchronized Keychain the accounts
/// use, and `AIUsageCache` keeps the four processes that draw them from each spending a fetch.

struct AIUsagePreferences: WidgetConfigurationIntent {

    static var title: LocalizedStringResource = "Select Assistant"
    static var description = IntentDescription("Selects which assistant's limits to show.")

    /// Unset means every connected assistant — which is what the wider families are for. The
    /// families with room for one shows the first connected one instead.
    @Parameter(title: "Assistant")
    var assistant: AIAssistant?

    init() { }
    init(assistant: AIAssistant?) {
        self.assistant = assistant
    }
}

struct AIUsageEntry: TimelineEntry {

    let date: Date
    let usage: [AIUsage]
    /// Why there is nothing to show, where there is nothing to show.
    var message: String?
    let configuration: AIUsagePreferences

    /// This entry, drawn at a later moment.
    func at(_ date: Date) -> AIUsageEntry {
        AIUsageEntry(date: date, usage: usage, message: message, configuration: configuration)
    }

    static let placeholder = AIUsageEntry(date: .now, usage: AIUsage.examples, configuration: AIUsagePreferences())
}

struct AIUsageProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> AIUsageEntry {
        .placeholder
    }

    func snapshot(for configuration: AIUsagePreferences, in context: Context) async -> AIUsageEntry {
        context.isPreview ? .placeholder : await entry(for: configuration)
    }

    func timeline(for configuration: AIUsagePreferences, in context: Context) async -> Timeline<AIUsageEntry> {
        let entry = await entry(for: configuration)
        let nextUpdate = nextUpdate(after: entry)
        return Timeline(entries: redraws(from: entry.date, to: nextUpdate).map { entry.at($0) }, policy: .after(nextUpdate))
    }

    /// The same figures redrawn until the next fetch, so the reset countdowns the accessories show
    /// keep counting down: every five minutes through the first day, where a countdown reads to the
    /// minute, then hourly — a week that has run out can be days from refilling, and a countdown
    /// that long reads only in days.
    private func redraws(from start: Date, to end: Date) -> [Date] {
        let day = start.addingTimeInterval(24 * 60 * 60)
        return Array(stride(from: start, to: min(end, day), by: 5 * 60)) + Array(stride(from: day, to: end, by: 60 * 60))
    }

    #if os(watchOS)
    /// What the watch face gallery offers before the wearer configures anything.
    ///
    /// Taken from the cache rather than from `AIAssistants`, which is main-actor isolated and so out
    /// of reach of a synchronous call. Before the first fetch there is nothing cached, and offering
    /// both assistants is the better guess than offering none.
    func recommendations() -> [AppIntentRecommendation<AIUsagePreferences>] {
        let cached = AIUsageCache.all().map(\.assistant)
        let assistants = cached.isEmpty ? AIAssistant.allCases : cached

        return assistants.map { assistant in
            AppIntentRecommendation(intent: AIUsagePreferences(assistant: assistant), description: Text(assistant.name))
        }
    }
    #endif

    private func entry(for configuration: AIUsagePreferences) async -> AIUsageEntry {
        let connected = await AIAssistants.shared.connected
        let wanted = configuration.assistant.map { connected.contains($0) ? [$0] : [] } ?? connected

        guard !wanted.isEmpty else {
            let error: AIUsageError = connected.isEmpty ? .notSignedIn : .signInExpired
            return AIUsageEntry(date: .now, usage: [], message: error.localizedDescription, configuration: configuration)
        }

        var usage: [AIUsage] = []
        var message: String?

        // One assistant at a time. Two at once could each find their sign-in expired and each
        // refresh it, and a refresh token used twice gets its family revoked — which would sign the
        // reader's terminal out too.
        for assistant in wanted {
            do {
                // A minute's grace, so a reading the open app has just handed over is used as it is.
                usage.append(try await AIAssistants.shared.usage(for: assistant, maxAge: 60))
            } catch {
                // One assistant failing should not blank the other, or throw away yesterday's
                // figures: stale numbers still say roughly where the week stands.
                if let cached = AIUsageCache.usage(for: assistant) {
                    usage.append(cached)
                } else if message == nil {
                    message = error.localizedDescription
                }
            }
        }

        return AIUsageEntry(date: .now, usage: usage, message: usage.isEmpty ? message : nil, configuration: configuration)
    }

    /// When to come back: whenever the assistant that needs it soonest does. With nothing to show,
    /// back off — an assistant that is not connected will not connect itself.
    private func nextUpdate(after entry: AIUsageEntry) -> Date {
        entry.usage.map { AIUsagePacing.nextCheck(for: $0, at: entry.date) }.min()
            ?? entry.date.addingTimeInterval(60 * 60)
    }
}

/// How often the AI usage widget asks about one assistant.
///
/// - A window that has run out cannot move until it refills, so the widget sleeps until it does.
/// - A five-hour window nobody has started moves only once work does: every half hour.
/// - Otherwise work is under way: every five minutes, doubling each time a new reading comes back
///   unchanged — the reader has stepped away — up to twenty, and back to five the moment one moves.
///
/// Five minutes is well past WidgetKit's daily reload budget if it ran all day, which is what the
/// doubling is for; and while the app is open it reads usage every minute and reloads this widget
/// itself, which the budget does not count.
///
/// Each timeline is a fresh run of the extension with no memory of the last, so what the pacing
/// has learned — the last reading it compared, and the interval that earned — lives in the App Group.
struct AIUsagePacing: Codable {

    var fiveHour: Double?
    var week: Double?
    var fetched: Date
    var interval: TimeInterval

    static let quickest: TimeInterval = 5 * 60
    static let slowest: TimeInterval = 20 * 60
    static let idle: TimeInterval = 30 * 60

    /// When to next ask about this reading's assistant, remembering what it learned for next time.
    static func nextCheck(for usage: AIUsage, at date: Date = .now) -> Date {
        var paces = stored()
        let previous = paces[usage.assistant.rawValue]

        let interval: TimeInterval
        if let previous, previous.fetched == usage.fetched {
            // The reading last time came back again, out of the cache: nothing new to learn from.
            interval = previous.interval
        } else if let previous, previous.fiveHour == usage.fiveHour?.used, previous.week == usage.week?.used {
            interval = min(previous.interval * 2, slowest)
        } else {
            interval = quickest
        }
        paces[usage.assistant.rawValue] = AIUsagePacing(fiveHour: usage.fiveHour?.used, week: usage.week?.used, fetched: usage.fetched, interval: interval)
        save(paces)

        if let refill = usage.exhaustedUntil(at: date) {
            return refill.addingTimeInterval(60)
        }
        if (usage.fiveHour?.used ?? 0) == 0 {
            return date.addingTimeInterval(idle)
        }
        return date.addingTimeInterval(interval)
    }

    /// Keyed by the assistant's raw value, which JSON keeps as an object rather than a list of pairs.
    private static func stored() -> [String: AIUsagePacing] {
        guard let data = UserDefaults.shared?.data(forKey: UserDefaults.Key.aiUsageWidgetPacing) else { return [:] }
        return (try? JSONDecoder().decode([String: AIUsagePacing].self, from: data)) ?? [:]
    }

    private static func save(_ paces: [String: AIUsagePacing]) {
        UserDefaults.shared?.set(try? JSONEncoder().encode(paces), forKey: UserDefaults.Key.aiUsageWidgetPacing)
    }
}

struct AIUsageWidget: Widget {
    let kind: String = AIUsageCache.widgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: AIUsagePreferences.self, provider: AIUsageProvider()) { entry in
            AIUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("AI Usage")
        .description("View how much of Claude's and Codex's limits you have left.")
        .supportedFamilies(AIUsageWidget.supportedFamilies)
    }

    /// No `.systemLarge`: two assistants and two windows each fill a medium, and a large would be
    /// the same four bars with more air around them. The Lock Screen families are the iPhone's
    /// alone, and the watch declares its own set.
    private static var supportedFamilies: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular]
        #elseif os(iOS)
        [.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline, .accessoryRectangular]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

// MARK: - Views

struct AIUsageWidgetView: View {

    @Environment(\.widgetFamily) private var family

    let entry: AIUsageEntry

    private var display: AIUsageDisplay { .current }

    /// The one assistant the narrow families show: the configured one, else whichever is closest to
    /// running out — the one whose limit is about to matter.
    private var headline: AIUsage? {
        entry.usage.map(display.relevant).max { ($0.tightestLimit?.used ?? 0) < ($1.tightestLimit?.used ?? 0) }
    }

    var body: some View {
        switch family {
        #if os(iOS) || os(watchOS)
        case .accessoryInline:
            inline
        case .accessoryRectangular:
            rectangular
                .containerBackground(for: .widget) { }
        case .accessoryCircular:
            circular
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        #endif
        #if os(watchOS)
        case .accessoryCorner:
            corner
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        #endif
        case .systemMedium:
            system(showingAll: true)
                .containerBackground(.fill.tertiary, for: .widget)
        default:
            system(showingAll: false)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    // MARK: Home screen

    @ViewBuilder
    func system(showingAll: Bool) -> some View {
        if entry.usage.isEmpty {
            AIUsageUnavailable(message: entry.message)
        } else {
            let shown = showingAll ? entry.usage : Array(headline.map { [$0] } ?? [])

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(shown) { usage in
                        AIUsageColumn(usage: usage, display: display)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // The oldest of the readings on screen: with one assistant's fetch failed and its
                // cached figures standing in, that is the one worth knowing the age of.
                if let read = entry.usage.map(\.fetched).min() {
                    Text(updated: read)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    // MARK: Accessories

    @ViewBuilder
    var inline: some View {
        if let usage = headline, let limit = usage.tightestLimit {
            Label("\(usage.assistant.name) \(display.summary(of: limit))", systemImage: usage.assistant.systemImage)
        } else {
            Label("AI Usage", systemImage: "gauge.with.dots.needle.33percent")
        }
    }

    /// The tightest window's bar, with the assistant above it and when that window resets between.
    @ViewBuilder
    var circular: some View {
        if let usage = headline, let window = usage.tightestWindow, let limit = usage[window] {
            VStack(spacing: 2) {
                Image(systemName: usage.assistant.systemImage)
                    .font(.body)
                    .widgetAccentable()

                Text(time(of: limit) ?? display.percentage(of: limit))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                AIUsageTrack(fraction: display.fraction(of: limit), tint: display.tint(for: limit, in: window))
                    .frame(width: 36)
            }
            .padding(6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(usage.assistant.name))
            .accessibilityValue(Text(display.summary(of: limit)))
        } else {
            AIUsageUnavailable(message: nil)
        }
    }

    /// When the limit resets, as the reader asked times to read — `nil` without one to show.
    private func time(of limit: AIUsageLimit) -> String? {
        guard let resetsAt = limit.resetsAt, resetsAt > entry.date else { return nil }
        return display.countdown(to: resetsAt, from: entry.date)
    }

    #if os(watchOS)
    /// The corner of a round face: the figure inside, the bar curved along the bezel.
    @ViewBuilder
    private var corner: some View {
        if let usage = headline, let limit = usage.tightestLimit {
            Text(display.percentage(of: limit))
                .widgetLabel {
                    Gauge(value: display.fraction(of: limit)) {
                        Text(usage.assistant.name)
                    }
                }
        } else {
            AIUsageUnavailable(message: nil)
        }
    }
    #endif

    /// The one accessory family with room for both windows.
    @ViewBuilder
    var rectangular: some View {
        if let usage = headline {
            VStack(alignment: .leading, spacing: 1) {
                Label(usage.assistant.name, systemImage: usage.assistant.systemImage)
                    .font(.headline)
                    .widgetAccentable()

                AIUsageBar(window: .fiveHour, usage: usage, display: display, showsReset: false, titlesReset: true, now: entry.date)
                AIUsageBar(window: .week, usage: usage, display: display, showsReset: false, titlesReset: true, now: entry.date)
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            AIUsageUnavailable(message: nil)
        }
    }
}

/// What a widget shows when there is nothing to draw. There is no room to explain in most of these
/// families, so it shows the mark and leaves the explaining to the app.
struct AIUsageUnavailable: View {

    let message: String?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .foregroundStyle(.secondary)

            if let message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if os(watchOS)
#Preview(as: .accessoryRectangular) {
    AIUsageWidget()
} timeline: {
    AIUsageEntry.placeholder
}
#else
#Preview(as: .systemMedium) {
    AIUsageWidget()
} timeline: {
    AIUsageEntry.placeholder
    AIUsageEntry(date: .now, usage: [], message: AIUsageError.notSignedIn.localizedDescription, configuration: AIUsagePreferences())
}

#Preview(as: .systemSmall) {
    AIUsageWidget()
} timeline: {
    AIUsageEntry.placeholder
}
#endif
