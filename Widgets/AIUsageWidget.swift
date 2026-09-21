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
        return Timeline(entries: [entry], policy: .after(nextUpdate(after: entry)))
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
                usage.append(try await AIAssistants.shared.usage(for: assistant))
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

    /// When to come back: shortly after the first window empties, or on the routine cadence,
    /// whichever is sooner.
    ///
    /// A reset is the one moment these figures jump — every other minute they only creep — so it is
    /// worth waking for. With nothing to show, back off: an assistant that is not connected will not
    /// connect itself.
    private func nextUpdate(after entry: AIUsageEntry) -> Date {
        guard !entry.usage.isEmpty else { return .now.addingTimeInterval(60 * 60) }

        let routine = Date.now.addingTimeInterval(2 * AIUsageCache.freshness)
        let nextReset = entry.usage
            .flatMap { [$0.fiveHour?.resetsAt, $0.week?.resetsAt] }
            .compactMap { $0 }
            .filter { $0 > .now }
            .min()?
            .addingTimeInterval(60)

        return min(routine, nextReset ?? routine)
    }
}

struct AIUsageWidget: Widget {
    let kind: String = "AIUsage"

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
        entry.usage.max { ($0.tightestLimit?.used ?? 0) < ($1.tightestLimit?.used ?? 0) }
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
    private func system(showingAll: Bool) -> some View {
        if entry.usage.isEmpty {
            AIUsageUnavailable(message: entry.message)
        } else {
            let shown = showingAll ? entry.usage : Array(headline.map { [$0] } ?? [])

            HStack(alignment: .top, spacing: 16) {
                ForEach(shown) { usage in
                    AIUsageColumn(usage: usage, display: display)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: Accessories

    @ViewBuilder
    private var inline: some View {
        if let usage = headline, let limit = usage.tightestLimit {
            Label("\(usage.assistant.name) \(display.summary(of: limit))", systemImage: usage.assistant.systemImage)
        } else {
            Label("AI Usage", systemImage: "gauge.with.dots.needle.33percent")
        }
    }

    @ViewBuilder
    private var circular: some View {
        if let usage = headline, let limit = usage.tightestLimit {
            Gauge(value: display.fraction(of: limit)) {
                Image(systemName: usage.assistant.systemImage)
            } currentValueLabel: {
                Text(display.percentage(of: limit))
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            AIUsageUnavailable(message: nil)
        }
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
    private var rectangular: some View {
        if let usage = headline {
            VStack(alignment: .leading, spacing: 1) {
                Label(usage.assistant.name, systemImage: usage.assistant.systemImage)
                    .font(.headline)
                    .widgetAccentable()

                AIUsageBar(window: .fiveHour, usage: usage, display: display, showsReset: false)
                AIUsageBar(window: .week, usage: usage, display: display, showsReset: false)
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
