import WidgetKit
import SwiftUI
import AppIntents

struct WidgetsEntryView: View {
    @Environment(\.widgetFamily) var size

    var entry: Provider.Entry

    var body: some View {
        if let data = entry.summary {
            switch size {
            case .systemSmall:
                SummarySmall(data: data, advanced: entry.configuration.advanced)
            #if os(iOS)
            case .accessoryCircular, .accessoryInline, .accessoryRectangular:
                AccessorySummary(summary: data)
            #endif
            default:
                SummaryWithChart(data: data, advanced: entry.configuration.advanced)
            }
        } else {
            #if os(iOS)
            if size != .systemSmall, size != .systemMedium, size != .systemLarge {
                AccessoryUnavailable()
            } else {
                ErrorWidget(error: entry.error ?? .unknown)
            }
            #else
            ErrorWidget(error: entry.error ?? .unknown)
            #endif
        }
    }
}

/// Everything this extension offers: the sales summary, and the AI usage widget the two extensions
/// share.
@main
struct AppSalesWidgets: WidgetBundle {
    var body: some Widget {
        Widgets()
        AIUsageWidget()
    }
}

struct Widgets: Widget {
    let kind: String = "Widgets"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetPreferences.self, provider: Provider()) { entry in
            WidgetsEntryView(entry: entry)
        }
        .configurationDisplayName("App Sales")
        .description("View app downloads and proceeds.")
        .supportedFamilies(Widgets.supportedFamilies)
    }

    /// The Lock Screen families are the iPhone's alone: the Mac and Vision have no home for them,
    /// and the watch declares its own set in `WatchWidgets`.
    private static var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryInline, .accessoryRectangular]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

#Preview(as: .systemSmall) {
    Widgets()
} timeline: {
    ACStatEntry(date: .now, data: .example, configuration: WidgetPreferences())
}

#if os(iOS)
#Preview(as: .accessoryRectangular) {
    Widgets()
} timeline: {
    ACStatEntry(date: .now, data: .example, configuration: WidgetPreferences())
}

#Preview(as: .accessoryCircular) {
    Widgets()
} timeline: {
    ACStatEntry(date: .now, data: .example, configuration: WidgetPreferences())
}
#endif
