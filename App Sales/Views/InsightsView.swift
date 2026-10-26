import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A collapsed "Insights" disclosure that uses on-device Apple Intelligence (Foundation Models)
/// to summarize the developer's recent performance, once opened. Renders nothing on platforms or
/// devices where the model is unavailable, so it is safe to drop into any list.
struct InsightsView: View {

    let summary: PerformanceSummary
    var funnel: [FunnelStage] = []

    var body: some View {
        if ScreenshotMode.isActive {
            // A screenshot run shows a fixed insight: the model is unavailable in the simulator, so
            // the section would not render there at all, and on the Mac it writes something
            // different every run. Neither makes a repeatable shot.
            InsightsSection(isExpanded: .constant(true)) {
                MarkdownText(ScreenshotMode.insight)
            }
        } else {
            #if canImport(FoundationModels)
            if #available(iOS 26, macOS 26, visionOS 26, *) {
                AppleIntelligenceInsights(summary: summary, funnel: funnel)
            }
            #endif
        }
    }
}

/// The model writes inline Markdown — bold above all — so it is rendered rather than shown as
/// asterisks. A stream cut mid-span parses as best it can; text that will not parse shows as written.
private struct MarkdownText: View {

    let markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }

    var body: some View {
        if let attributed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
        } else {
            Text(verbatim: markdown)
        }
    }
}

/// The Insights section's chrome, shared by the generated insight and the screenshot run's fixed one:
/// one row until opened, so it takes no more room than the reader gives it.
private struct InsightsSection<Content: View>: View {

    @Binding var isExpanded: Bool
    var showsDisclaimer = true
    @ViewBuilder let content: Content

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                content
            } label: {
                Label("Insights", systemImage: "apple.intelligence")
            }
        } footer: {
            if isExpanded && showsDisclaimer {
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
    /// Whether the reader has the insights open. Nothing is generated until they do; while open, new
    /// figures are written about as they arrive. Closing keeps the text for the next look.
    var isExpanded = false

    /// The numbers `insight` describes. Generation only restarts when they change.
    private var key: String?
    private var task: Task<Void, Never>?

    private init() {}

    /// Starts generating for `summary` and `funnel`, unless the insight on hand already describes them.
    func generate(for summary: PerformanceSummary, funnel: [FunnelStage]) {
        let key = Self.key(for: summary, funnel: funnel)
        guard key != self.key else { return }

        self.key = key
        task?.cancel()
        insight = ""
        failed = false
        task = Task { await self.write(key: key, prompt: Self.prompt(for: summary, funnel: funnel)) }
    }

    private func write(key: String, prompt: String) async {
        do {
            let session = LanguageModelSession {
                """
                You are an analyst helping an App Store developer understand their sales. \
                Given 30-day metrics compared to the previous 30 days, write 2 to 3 short, \
                specific takeaways as a single short paragraph. Call out the overall trend, \
                and the standout or struggling app when one is clear. When a conversion funnel \
                is given, note the weakest step if it stands out. When proceeds are split into \
                App Store sales and ad earnings, say which is driving the change. Be concise, factual, \
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
    static func key(for summary: PerformanceSummary, funnel: [FunnelStage]) -> String {
        ([summary.downloads, summary.prevDownloads, Int(summary.proceeds), Int(summary.prevProceeds), Int(summary.adProceeds), Int(summary.prevAdProceeds)] + funnel.map(\.count))
            .map(String.init)
            .joined(separator: "-")
    }

    private static func prompt(for summary: PerformanceSummary, funnel: [FunnelStage]) -> String {
        let currency = NumberFormatter.currency
        func money(_ value: Double) -> String { currency.string(from: NSNumber(value: value)) ?? "\(value)" }
        // Only a reader with ads gets the split, so the model does not write about ad earnings of zero.
        let hasAds = summary.adProceeds > 0 || summary.prevAdProceeds > 0

        var proceedsLine = "Proceeds: \(money(summary.proceeds)) (previously \(money(summary.prevProceeds)))"
        if hasAds {
            proceedsLine += "\n- App Store sales: \(money(summary.proceeds - summary.adProceeds)) (previously \(money(summary.prevProceeds - summary.prevAdProceeds)))"
            proceedsLine += "\n- Ad earnings: \(money(summary.adProceeds)) (previously \(money(summary.prevAdProceeds)))"
        }

        let appLines = summary.topApps
            .map { app in
                var line = "- \(app.name): \(app.downloads) downloads, \(money(app.proceeds)) proceeds"
                if hasAds {
                    line += " (\(money(app.proceeds - app.adProceeds)) App Store sales, \(money(app.adProceeds)) ad earnings)"
                }
                return line
            }
            .joined(separator: "\n")

        return """
        Last 30 days vs. the previous 30 days:

        Downloads: \(summary.downloads) (previously \(summary.prevDownloads))
        \(proceedsLine)

        Top apps over the last 30 days:
        \(appLines.isEmpty ? "- (no app breakdown available)" : appLines)
        \(funnel.isEmpty ? "" : "\nConversion funnel over the latest 30 days of App Store analytics, each step with the share of the step before that reached it:\n" + funnelLines(funnel))
        """
    }

    private static func funnelLines(_ funnel: [FunnelStage]) -> String {
        funnel.enumerated()
            .map { index, stage in
                var line = "- \(name(of: stage.stat)): \(stage.count)"
                if index > 0, funnel[index - 1].count > 0 {
                    line += " (\((Double(stage.count) / Double(funnel[index - 1].count)).formatted(.percent.precision(.fractionLength(0...1)))))"
                }
                return line
            }
            .joined(separator: "\n")
    }

    /// The stage's name for the model, which reads English whatever the reader's language.
    private static func name(of stat: AppListSort) -> String {
        switch stat {
        case .websiteViews: "Developer website page views"
        case .appStoreViews: "App Store product page views"
        case .downloads: "Downloads"
        case .activeDevices: "Average daily active devices"
        default: stat.rawValue
        }
    }
}

@available(iOS 26, macOS 26, visionOS 26, *)
private struct AppleIntelligenceInsights: View {

    let summary: PerformanceSummary
    let funnel: [FunnelStage]

    @State private var store = InsightsStore.shared

    private let model = SystemLanguageModel.default

    var body: some View {
        if case .available = model.availability {
            InsightsSection(isExpanded: $store.isExpanded, showsDisclaimer: !store.insight.isEmpty) {
                if store.failed {
                    Label("Couldn't generate insights right now.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else if store.insight.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Analyzing…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    MarkdownText(store.insight)
                        .textSelection(.enabled)
                }
            }
            // Runs once opened, then on appear and whenever the figures change; the store ignores a
            // repeat of numbers it has already written about, which is what a scroll back or reopen looks like.
            .task(id: store.isExpanded ? InsightsStore.key(for: summary, funnel: funnel) : nil) {
                guard store.isExpanded else { return }

                store.generate(for: summary, funnel: funnel)
            }
        }
    }
}
#endif
