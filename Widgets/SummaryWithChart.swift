import SwiftUI
import WidgetKit
import AppSalesKit

struct SummaryWithChart: View {

    let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.negativePrefix = ""
        return formatter
    }()
    var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
//        formatter.currencyCode =
        return formatter
    }
    let data: PerformanceSummary
    let advanced: Bool
    let family: WidgetFamily

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        header
                        Spacer(minLength: 0)
                        stats(alignment: .leading)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    graph
                }
            } else {
                VStack {
                    header
                        .frame(idealWidth: .infinity, maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .trailing) {
                            stats(alignment: .trailing)
                        }

                    graph
                }
            }
        }
        .allowsTightening(true)
        .containerBackground(.background, for: .widget)
    }

    private var header: some View {
        VStack(alignment: .leading) {
            Text("App Sales")
                .font(.headline)
                .widgetAccentable()
            Text("30 days")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func stats(alignment: Alignment) -> some View {
        Grid(alignment: alignment) {
            GridRow {
                Text(currencyFormatter.string(from: NSNumber(value: data.proceeds)) ?? "")
                change(data.proceedsPercentageChange)
            }

            GridRow {
                Text("\(Text(Image(systemName: "arrow.down.app")).foregroundStyle(.secondary))\(data.downloads)")
                change(data.downloadsPercentageChange)
            }
        }
        .fontWeight(.medium)
    }

    private func change(_ fraction: Double) -> some View {
        Text("\(Image(systemName: fraction < 0 ? "arrow.down.forward" : "arrow.up.forward"))\(percentFormatter.string(from: NSNumber(value: fraction)) ?? "")")
            .font(.callout)
            .foregroundStyle(fraction < 0 ? Color.red : Color.green)
    }

    @ViewBuilder
    private var graph: some View {
        if advanced || family == .systemLarge {
            DownloadsAndProceedsChart(apps: data.apps, iconLength: family == .systemMedium ? 20 : 22)
                .chartLegend(.hidden)
        } else {
            DownloadsBarsGraphic(apps: data.apps)
        }
    }
}
