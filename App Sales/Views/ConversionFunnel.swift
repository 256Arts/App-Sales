import SwiftUI

/// One step of the funnel: a count of people or devices.
struct FunnelStage: Identifiable {
    let stat: AppListSort
    let color: Color
    let count: Int
    /// The change on the 30 days before, when there is a figure to compare with.
    var change: Double?

    var id: AppListSort { stat }
}

/// The funnel from the webpage to active devices, a row per stage: its name, figure, and trend, with
/// the share of the stage before that made it through, over a bar centred and as wide as its share of the widest,
/// so the bars taper like a funnel across the full width.
struct ConversionFunnel: View {

    let stages: [FunnelStage]

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// Trends only where there is room for them: a compact row has no space beside the share and figure.
    private var showsTrends: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
        #endif
    }

    private var widest: Int {
        stages.map(\.count).max() ?? 0
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Label {
                            Text(stage.stat.title)
                        } icon: {
                            Image(systemName: stage.stat.systemImage)
                                .symbolVariant(.fill)
                                .foregroundStyle(stage.color)
                        }
                        Spacer(minLength: 0)
                        if index > 0, stages[index - 1].count > 0 {
                            Text(Double(stage.count) / Double(stages[index - 1].count), format: .percent.precision(.fractionLength(0...1)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(stage.count.formatted())
                            .fontWeight(.semibold)
                            .layoutPriority(1)
                        if showsTrends, let change = stage.change {
                            PercentChange(change: change)
                                .font(.caption)
                                .layoutPriority(1)
                        }
                    }
                    .lineLimit(1)
                    .monospacedDigit()

                    GeometryReader { proxy in
                        Capsule()
                            .fill(stage.color.gradient)
                            // Never thinner than a dot, so a stage that let nobody through still shows.
                            .frame(width: max(proxy.size.height, proxy.size.width * CGFloat(stage.count) / CGFloat(max(widest, 1))))
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: 8)
                }
                .accessibilityElement(children: .combine)
                // The screenshot walk scrolls until this is in view.
                .accessibilityIdentifier(index == stages.count - 1 ? "Funnel.Last" : "")
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        ConversionFunnel(stages: [
            FunnelStage(stat: .websiteViews, color: .teal, count: 4_200, change: 0.12),
            FunnelStage(stat: .appStoreViews, color: .indigo, count: 12_800, change: -0.04),
            FunnelStage(stat: .downloads, color: .blue, count: 3_100, change: 0.08),
            FunnelStage(stat: .activeDevices, color: .orange, count: 840, change: 0.21),
        ])
    }
}
