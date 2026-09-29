import WidgetKit
import SwiftUI

// The accessory families exist only where something wears them: the iPhone's Lock Screen and the
// watch face. `WidgetFamily` has no such cases on macOS or visionOS.
#if os(iOS) || os(watchOS)

/// The accessory families, shared by the iPhone's Lock Screen widgets and the watch's complications.
///
/// Same shapes, same sizes, same job — a number to read without unlocking anything — so the two
/// extensions render the same views and differ only in which families they declare.
struct AccessorySummary: View {

    @Environment(\.widgetFamily) private var family

    let summary: PerformanceSummary

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                InlineAccessory(summary: summary)
            case .accessoryRectangular:
                RectangularAccessory(summary: summary)
            #if os(watchOS)
            case .accessoryCorner:
                CornerAccessory(summary: summary)
            #endif
            default:
                CircularAccessory(summary: summary)
            }
        }
        .containerBackground(for: .widget) {
            // Only the round families take a backing plate; rectangular and inline sit flat on the
            // Lock Screen or the watch face.
            if isRound {
                AccessoryWidgetBackground()
            }
        }
    }

    private var isRound: Bool {
        #if os(watchOS)
        family == .accessoryCircular || family == .accessoryCorner
        #else
        family == .accessoryCircular
        #endif
    }
}

/// What an accessory family shows when the fetch failed. There is no room to explain, so it shows
/// the app's mark and lets the app itself say what went wrong.
struct AccessoryUnavailable: View {

    var body: some View {
        Image(systemName: "chart.bar.xaxis")
            .foregroundStyle(.secondary)
            .containerBackground(for: .widget) { }
    }
}

// MARK: - Families

/// One line beside the time: proceeds and which way they moved.
struct InlineAccessory: View {

    let summary: PerformanceSummary

    var body: some View {
        Label(
            "\(summary.compactProceeds) · \(summary.downloads.formatted())",
            systemImage: summary.trendSystemImage)
    }
}

/// A ring that fills as the last 30 days catch up to the 30 before them, wrapped around the
/// proceeds figure — so a full ring means the period matched or beat the one before it.
struct CircularAccessory: View {

    let summary: PerformanceSummary

    var body: some View {
        Gauge(value: summary.proceedsProgress) {
            Image(systemName: summary.trendSystemImage)
        } currentValueLabel: {
            Text(summary.compactProceeds)
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
    }
}

#if os(watchOS)
/// The corner of a round face: proceeds, with downloads curved along the bezel.
private struct CornerAccessory: View {

    let summary: PerformanceSummary

    var body: some View {
        Text(summary.compactProceeds)
            .widgetLabel {
                Label(summary.downloads.formatted(), systemImage: "arrow.down.app")
            }
    }
}
#endif

/// The one family with room for both metrics and both trends.
struct RectangularAccessory: View {

    let summary: PerformanceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("App Sales")
                .font(.headline)
                .widgetAccentable()

            metric(summary.compactProceeds, change: summary.proceedsPercentageChange)
            metric(summary.downloads.formatted(), systemImage: "arrow.down.app", change: summary.downloadsPercentageChange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ value: String, systemImage: String? = nil, change: Double) -> some View {
        HStack(spacing: 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            Text(value)
            Image(systemName: change < 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                .imageScale(.small)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

// MARK: - Accessory-sized values

private extension PerformanceSummary {

    /// Proceeds abbreviated, because none of these families fit "$12,345.67". One decimal place is
    /// worth keeping: it is the difference between "$2.8K" and a flat "$3K".
    var compactProceeds: String {
        proceeds.formatted(
            .currency(code: Locale.autoupdatingCurrent.currency?.identifier ?? "USD")
            .notation(.compactName)
            .precision(.fractionLength(0...1)))
    }

    var trendSystemImage: String {
        proceedsPercentageChange < 0 ? "arrow.down.forward" : "arrow.up.forward"
    }

    /// How far the last 30 days got towards matching the 30 before them, clamped to a full ring.
    /// With no prior proceeds to beat, any sale at all counts as full.
    var proceedsProgress: Double {
        guard prevProceeds > 0 else { return 0 < proceeds ? 1 : 0 }

        return min(proceeds / prevProceeds, 1)
    }
}

#endif
