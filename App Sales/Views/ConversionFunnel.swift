import SwiftUI

/// One step of the funnel: a count of people or devices, or the proceeds it ends in.
struct FunnelStage: Identifiable {
    let stat: AppListSort
    let color: Color
    let value: Value

    var id: AppListSort { stat }

    enum Value {
        case count(Int)
        case proceeds(Double)
    }

    var count: Int? {
        if case .count(let count) = value { count } else { nil }
    }
}

/// The funnel from the webpage to proceeds, a row per stage: its name, a bar centred and as wide as
/// its share of the widest, and its figure over the share of the stage before that made it through.
/// Proceeds are money, not people, so they close the funnel as a figure per download rather than a bar.
struct ConversionFunnel: View {

    let stages: [FunnelStage]

    private var downloads: Int {
        stages.first { $0.stat == .downloads }?.count ?? 0
    }

    private var widest: Int {
        stages.compactMap(\.count).max() ?? 0
    }

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 10) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                GridRow {
                    Label {
                        Text(stage.stat.title)
                    } icon: {
                        Image(systemName: stage.stat.systemImage)
                            .symbolVariant(.fill)
                            .foregroundStyle(stage.color)
                    }
                    .gridColumnAlignment(.leading)

                    bar(for: stage)

                    VStack(alignment: .trailing, spacing: 0) {
                        Text(formatted(stage.value))
                            .fontWeight(.semibold)
                        if index > 0 {
                            step(from: stages[index - 1], to: stage)
                        }
                    }
                    .monospacedDigit()
                    .gridColumnAlignment(.trailing)
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func bar(for stage: FunnelStage) -> some View {
        if let count = stage.count {
            GeometryReader { proxy in
                Capsule()
                    .fill(stage.color.gradient)
                    // Never thinner than a dot, so a stage that let nobody through still shows.
                    .frame(width: max(proxy.size.height, proxy.size.width * CGFloat(count) / CGFloat(max(widest, 1))))
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 14)
        } else {
            Color.clear
                .frame(height: 14)
        }
    }

    /// The share of the stage before that reached this one; or, for proceeds, what each download earned.
    @ViewBuilder
    private func step(from previous: FunnelStage, to stage: FunnelStage) -> some View {
        Group {
            switch stage.value {
            case .count(let count) where (previous.count ?? 0) > 0:
                Text(Double(count) / Double(previous.count ?? 1), format: .percent.precision(.fractionLength(0...1)))
            case .proceeds(let proceeds) where downloads > 0:
                Text("\(NumberFormatter.currency.string(from: NSNumber(value: proceeds / Double(downloads))) ?? "") per download")
            default:
                EmptyView()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func formatted(_ value: FunnelStage.Value) -> String {
        switch value {
        case .count(let count): count.formatted()
        case .proceeds(let proceeds): NumberFormatter.currency.string(from: NSNumber(value: proceeds)) ?? ""
        }
    }
}

#Preview {
    List {
        ConversionFunnel(stages: [
            FunnelStage(stat: .websiteViews, color: .teal, value: .count(4_200)),
            FunnelStage(stat: .appStoreViews, color: .indigo, value: .count(12_800)),
            FunnelStage(stat: .downloads, color: .blue, value: .count(3_100)),
            FunnelStage(stat: .activeDevices, color: .orange, value: .count(840)),
            FunnelStage(stat: .proceeds, color: .green, value: .proceeds(1_240)),
        ])
    }
}
