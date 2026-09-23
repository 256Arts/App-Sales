import Foundation

/// The last figures read for each assistant, in the App Group beside the sales cache.
///
/// A usage fetch is not as cheap as it looks. Both assistants hand out refresh tokens that rotate,
/// and a token used twice gets its whole family revoked — which would sign the reader's own terminal
/// out, not just App Sales. `AIAssistants` keeps one fetch per assistant in flight, but only within
/// a process, and part 2 adds three more processes that want the same numbers: the widget extension,
/// the watch's, and the Mac's menu bar extra. This is what stops each of them being that process at
/// the same moment, and it is also what lets a widget draw something the instant it is placed.
enum AIUsageCache {

    /// How long a reading is worth showing before someone should go and ask again.
    ///
    /// Tuned to the shorter of the two windows: a five-hour limit moves by about 5% in fifteen
    /// minutes of steady work, which is under the rounding on every figure App Sales draws.
    static let freshness: TimeInterval = 15 * 60

    /// The AI usage widget's kind, for the app to reload it by once it has read something new.
    static let widgetKind = "AIUsage"

    private static let fileName = "ai-usage-cache.json"

    private static var storageURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// Everything cached, however old — what a widget draws while its own fetch is still in flight.
    static func all() -> [AIUsage] {
        // The menu bar extra reads nothing else, so this is where a screenshot run gets its figures.
        if ScreenshotMode.isActive { return AIUsage.examples }

        guard let storageURL, let data = try? Data(contentsOf: storageURL) else { return [] }

        return (try? JSONDecoder().decode([AIUsage].self, from: data)) ?? []
    }

    static func usage(for assistant: AIAssistant) -> AIUsage? {
        all().first { $0.assistant == assistant }
    }

    /// The cached reading, or `nil` once it is older than `maxAge`.
    static func usage(for assistant: AIAssistant, newerThan maxAge: TimeInterval) -> AIUsage? {
        guard let usage = usage(for: assistant), usage.fetched.timeIntervalSinceNow > -maxAge else { return nil }

        return usage
    }

    static func save(_ usage: AIUsage) {
        var cached = all()
        cached.removeAll { $0.assistant == usage.assistant }
        cached.append(usage)
        write(cached)
    }

    static func clear(_ assistant: AIAssistant) {
        write(all().filter { $0.assistant != assistant })
    }

    private static func write(_ usage: [AIUsage]) {
        guard let storageURL, let data = try? JSONEncoder().encode(usage) else { return }

        try? data.write(to: storageURL)
    }
}
