import WidgetKit
import SwiftUI

/// The watch face complications. The views are `AccessorySummary`, shared with the Lock Screen
/// widgets on iPhone; only the family list differs, because `.accessoryCorner` is watchOS's alone.
/// Everything the watch offers: the sales complications, and the AI usage complications the two
/// extensions share.
@main
struct AppSalesWatchWidgets: WidgetBundle {
    var body: some Widget {
        WatchWidgets()
        AIUsageWidget()
    }
}

struct WatchWidgets: Widget {
    let kind: String = "WatchWidgets"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetPreferences.self, provider: Provider()) { entry in
            if let summary = entry.summary {
                AccessorySummary(summary: summary)
            } else {
                AccessoryUnavailable()
            }
        }
        .configurationDisplayName("App Sales")
        .description("View app downloads and proceeds.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

#Preview(as: .accessoryRectangular) {
    WatchWidgets()
} timeline: {
    ACStatEntry(date: .now, data: .example, configuration: WidgetPreferences())
}

#Preview(as: .accessoryCircular) {
    WatchWidgets()
} timeline: {
    ACStatEntry(date: .now, data: .example, configuration: WidgetPreferences())
}
