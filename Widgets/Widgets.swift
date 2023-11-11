//
//  Widgets.swift
//  AC Widget by NO-COMMENT
//

import WidgetKit
import SwiftUI
import AppIntents

struct WidgetPreferences: WidgetConfigurationIntent {
    
    static var title: LocalizedStringResource = "Select Account"
    static var description = IntentDescription("Selects the account to display information for.")

    @Parameter(title: "Account")
    var account: Account
    
    @Parameter(title: "Advanced", default: true)
    var advanced: Bool

    init() { }
    init(account: Account, advanced: Bool) {
        self.account = account
        self.advanced = advanced
    }
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ACStatEntry {
        ACStatEntry(date: Date(), data: .example, configuration: WidgetPreferences())
    }

    func snapshot(for configuration: WidgetPreferences, in context: Context) async -> ACStatEntry {
        if context.isPreview {
            return .placeholder
        } else {
            do {
                let data = try await getApiData(apiKey: configuration.account)
                let isNewData = data.getRawData(for: .proceeds, lastNDays: 3).contains { (proceed) -> Bool in
                    Calendar.current.isDateInToday(proceed.1) ||
                    Calendar.current.isDateInYesterday(proceed.1)
                }

                let entry = ACStatEntry(
                    date: Date(),
                    data: data,
                    configuration: configuration,
                    relevance: isNewData ? .high : .medium
                )
                return entry
            } catch let err {
                let entry = ACStatEntry(date: Date(), data: nil, error: err as? APIError ?? .unknown, configuration: configuration, relevance: .low)
                return entry
            }
        }
    }

    func timeline(for configuration: WidgetPreferences, in context: Context) async -> Timeline<ACStatEntry> {
        do {
            let data = try await getApiData(apiKey: configuration.account)
            let isNewData = data.getRawData(for: .proceeds, lastNDays: 3).contains { (proceed) -> Bool in
                Calendar.autoupdatingCurrent.isDateInToday(proceed.1) ||
                Calendar.autoupdatingCurrent.isDateInYesterday(proceed.1)
            }

            let entry = ACStatEntry(date: Date(), data: data, configuration: configuration, relevance: isNewData ? .high : .medium)

            // Report is not available yet. Daily reports for the Americas are available by 5 am Pacific Time; Japan, Australia, and New Zealand by 5 am Japan Standard Time; and 5 am Central European Time for all other territories.

            var nextUpdate = Date()

            if nextUpdate.getCETHour() <= 12 {
                // every 15 minutes
                nextUpdate = nextUpdate.advanced(by: 15 * 60)
            } else {
                nextUpdate = nextUpdate.nextFullHour()
            }

            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            return timeline
        } catch let err as APIError {
            let entry = ACStatEntry(date: Date(), data: nil, error: err, configuration: configuration)

            var nextUpdateDate = Date()
            if err == .invalidCredentials {
                nextUpdateDate = nextUpdateDate.advanced(by: 24 * 60)
            } else {
                // when api down, update in 5 min erneut
                nextUpdateDate = nextUpdateDate.advanced(by: 5 * 60)
            }

            let timeline = Timeline(entries: [entry], policy: .after(nextUpdateDate))
            return timeline
        } catch {
            let entry = ACStatEntry(date: Date(), data: nil, error: APIError.unknown, configuration: configuration)

            // when api down, update in 5 min erneut
            let timeline = Timeline(entries: [entry], policy: .after(Date().advanced(by: 5 * 60)))
            return timeline
        }
    }

    func getApiData(apiKey: Account?) async throws -> ACData {
        guard let apiKey,
              AccountProvider.shared.getApiKey(apiKeyId: apiKey.id) != nil else {
                  throw APIError.invalidCredentials
              }
        let api = AppStoreConnectAPI(apiKey: apiKey)
        return try await api.getData()
    }
}

struct ACStatEntry: TimelineEntry {
    
    let date: Date
    let summary: PerformanceSummary?
    var error: APIError?
    let configuration: WidgetPreferences
    var relevance: TimelineEntryRelevance?
    
    init(date: Date, data: ACData?, error: APIError? = nil, configuration: WidgetPreferences, relevance: TimelineEntryRelevance? = nil) {
        self.date = date
        self.summary = data?.getPerformanceSummary()
        self.error = error
        self.configuration = configuration
        self.relevance = relevance
    }
    
    static let placeholder = ACStatEntry(date: Date(), data: .example, configuration: WidgetPreferences())
}

extension TimelineEntryRelevance {
    static let low = TimelineEntryRelevance(score: 0, duration: 0)
    static let medium = TimelineEntryRelevance(score: 50, duration: 60 * 60)
    static let high = TimelineEntryRelevance(score: 100, duration: 60 * 60)
}

struct WidgetsEntryView: View {
    @Environment(\.widgetFamily) var size

    var entry: Provider.Entry

    var body: some View {
        if let data = entry.summary {
            switch size {
            case .systemSmall:
                SummarySmall(data: data, advanced: entry.configuration.advanced)
            case .systemMedium, .systemLarge:
                SummaryWithChart(data: data, advanced: entry.configuration.advanced)
            default:
                ErrorWidget(error: .unknown)
            }
        } else {
            ErrorWidget(error: entry.error ?? .unknown)
        }
    }
}

@main
struct Widgets: Widget {
    let kind: String = "Widgets"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetPreferences.self, provider: Provider()) { entry in
            WidgetsEntryView(entry: entry)
        }
        .configurationDisplayName("App Sales")
        .description("View app downloads and proceeds.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview {
    WidgetsEntryView(entry: ACStatEntry(date: Date(), data: .example, configuration: WidgetPreferences()))
}
#Preview {
    WidgetsEntryView(entry: ACStatEntry(date: Date(), data: .example, configuration: WidgetPreferences()))
}
