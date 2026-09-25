import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A "Insights" section that uses on-device Apple Intelligence (Foundation Models)
/// to summarize the developer's recent performance, once asked to. Renders nothing on platforms or
/// devices where the model is unavailable, so it is safe to drop into any list.
struct InsightsView: View {

    let summary: PerformanceSummary

    var body: some View {
        if ScreenshotMode.isActive {
            // A screenshot run shows a fixed insight: the model is unavailable in the simulator, so
            // the section would not render there at all, and on the Mac it writes something
            // different every run. Neither makes a repeatable shot.
            InsightsSection {
                Text(ScreenshotMode.insight)
            }
        } else {
            #if canImport(FoundationModels)
            if #available(iOS 26, macOS 26, visionOS 26, *) {
                AppleIntelligenceInsights(summary: summary)
            }
            #endif
        }
    }
}

/// The Insights section's chrome, shared by the generated insight and the screenshot run's fixed one.
private struct InsightsSection<Content: View>: View {

    var showsDisclaimer = true
    @ViewBuilder let content: Content

    var body: some View {
        Section {
            content
        } header: {
            Label("Insights", systemImage: "apple.intelligence")
        } footer: {
            if showsDisclaimer {
                Text("Generated on-device by Apple Intelligence. May contain mistakes.")
            }
        }
    }
}

#if canImport(FoundationModels)
/// Holds the generated insight outside the view hierarchy.
///
/// The section sits in the home screen's `List`, so scrolling it off screen tears the row's state
/// down and cancels anything a `.task` was running. Kept in the view, that meant every scroll back
/// threw the paragraph away and spent the model writing it again. The text and the generating task
/// live here instead, keyed by the numbers they describe, so a second look is free and a stream
/// that started before the row scrolled away finishes into the same place.
@available(iOS 26, macOS 26, visionOS 26, *)
@MainActor
@Observable
final class InsightsStore {

    static let shared = InsightsStore()

    private(set) var insight = ""
    private(set) var failed = false
    /// Whether the reader asked for insights. Nothing is generated until they do; after that, new
    /// figures are written about as they arrive, until the app quits.
    var isRequested = false

    /// The numbers `insight` describes. Generation only restarts when they change.
    private var key: String?
    private var task: Task<Void, Never>?

    private init() {}

    /// Starts generating for `summary`, unless the insight on hand already describes it.
    func generate(for summary: PerformanceSummary) {
        let key = Self.key(for: summary)
        guard key != self.key else { return }

        self.key = key
        task?.cancel()
        insight = ""
        failed = false
        task = Task { await self.write(key: key, prompt: Self.prompt(for: summary)) }
    }

    private func write(key: String, prompt: String) async {
        do {
            let session = LanguageModelSession {
                """
                You are an analyst helping an App Store developer understand their sales. \
                Given 30-day metrics compared to the previous 30 days, write 2 to 3 short, \
                specific takeaways as a single short paragraph. Call out the overall trend, \
                and the standout or struggling app when one is clear. Be concise, factual, \
                and encouraging but honest. Never invent numbers that aren't provided.
                """
            }
            // Stream so takeaways appear as they're written, rather than after the full response.
            for try await snapshot in session.streamResponse(to: prompt) {
                // Newer numbers arrived and took over; this run's output is stale.
                guard key == self.key else { return }

                insight = snapshot.content
            }
        } catch {
            guard key == self.key else { return }

            failed = true
            // Forget the key so the next look tries again rather than showing the failure forever.
            self.key = nil
        }
    }

    /// Identifies a summary by the figures the prompt actually reports, so a refetch that returns
    /// the same day's numbers does not rewrite the paragraph.
    static func key(for summary: PerformanceSummary) -> String {
        "\(summary.downloads)-\(summary.prevDownloads)-\(Int(summary.proceeds))-\(Int(summary.prevProceeds))"
    }

    private static func prompt(for summary: PerformanceSummary) -> String {
        let currency = NumberFormatter.currency
        let proceeds = currency.string(from: NSNumber(value: summary.proceeds)) ?? "\(summary.proceeds)"
        let prevProceeds = currency.string(from: NSNumber(value: summary.prevProceeds)) ?? "\(summary.prevProceeds)"

        let appLines = summary.topApps
            .map { app in
                let appProceeds = currency.string(from: NSNumber(value: app.proceeds)) ?? "\(app.proceeds)"
                return "- \(app.name): \(app.downloads) downloads, \(appProceeds) proceeds"
            }
            .joined(separator: "\n")

        return """
        Last 30 days vs. the previous 30 days:

        Downloads: \(summary.downloads) (previously \(summary.prevDownloads))
        Proceeds: \(proceeds) (previously \(prevProceeds))

        Top apps over the last 30 days:
        \(appLines.isEmpty ? "- (no app breakdown available)" : appLines)
        """
    }
}

@available(iOS 26, macOS 26, visionOS 26, *)
private struct AppleIntelligenceInsights: View {

    let summary: PerformanceSummary

    @State private var store = InsightsStore.shared

    private let model = SystemLanguageModel.default

    var body: some View {
        if case .available = model.availability {
            InsightsSection(showsDisclaimer: store.isRequested && !store.insight.isEmpty) {
                if !store.isRequested {
                    Button("Summarize My Sales", systemImage: "apple.intelligence") {
                        store.isRequested = true
                    }
                } else if store.failed {
                    Label("Couldn't generate insights right now.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else if store.insight.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Analyzing…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(store.insight)
                        .textSelection(.enabled)
                }
            }
            // Runs once asked, then on appear and whenever the figures change; the store ignores a
            // repeat of numbers it has already written about, which is what a scroll back looks like.
            .task(id: store.isRequested ? InsightsStore.key(for: summary) : nil) {
                guard store.isRequested else { return }

                store.generate(for: summary)
            }
        }
    }
}
#endif
