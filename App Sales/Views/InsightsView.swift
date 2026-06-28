//
//  InsightsView.swift
//  AC Widget by NO-COMMENT
//

import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A "Insights" section that uses on-device Apple Intelligence (Foundation Models)
/// to summarize the developer's recent performance. Renders nothing on platforms or
/// devices where the model is unavailable, so it is safe to drop into any list.
struct InsightsView: View {

    let summary: PerformanceSummary

    var body: some View {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            AppleIntelligenceInsights(summary: summary)
        }
        #endif
    }
}

#if canImport(FoundationModels)
@available(iOS 26, macOS 26, visionOS 26, *)
private struct AppleIntelligenceInsights: View {

    let summary: PerformanceSummary

    @State private var insight: String = ""
    @State private var failed = false

    private let model = SystemLanguageModel.default

    var body: some View {
        if case .available = model.availability {
            Section {
                if failed {
                    Label("Couldn't generate insights right now.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else if insight.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Analyzing…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(insight)
                        .textSelection(.enabled)
                }
            } header: {
                Label("Insights", systemImage: "apple.intelligence")
            } footer: {
                if !insight.isEmpty {
                    Text("Generated on-device by Apple Intelligence. May contain mistakes.")
                }
            }
            .task(id: regenerationKey) {
                await generate()
            }
        }
    }

    /// Re-runs generation whenever the underlying numbers change.
    private var regenerationKey: String {
        "\(summary.downloads)-\(summary.prevDownloads)-\(Int(summary.proceeds))-\(Int(summary.prevProceeds))"
    }

    private func generate() async {
        failed = false
        insight = ""
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
                insight = snapshot.content
            }
        } catch {
            failed = true
        }
    }

    private var prompt: String {
        let currency = currencyFormatter
        let proceeds = currency.string(from: NSNumber(value: summary.proceeds)) ?? "\(summary.proceeds)"
        let prevProceeds = currency.string(from: NSNumber(value: summary.prevProceeds)) ?? "\(summary.prevProceeds)"

        let appLines = summary.apps
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

    private var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter
    }
}
#endif
