//
//  SummaryWithChart.swift
//  AC Widget by NO-COMMENT
//

import SwiftUI
import WidgetKit

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
    
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                Text("App Sales")
                    .font(.headline)
                Text("30 days")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(idealWidth: .infinity, maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                Grid(alignment: .trailing) {
                    GridRow {
                        Text(currencyFormatter.string(from: NSNumber(value: data.proceeds)) ?? "")
                        Text("\(Image(systemName: data.proceedsPercentageChange < 0 ? "arrow.down.forward" : "arrow.up.forward"))\(percentFormatter.string(from: NSNumber(value: data.proceedsPercentageChange)) ?? "")")
                            .font(.callout)
                            .foregroundStyle(data.proceedsPercentageChange < 0 ? Color.red : Color.green)
                    }
                    
                    GridRow {
                        Text("\(Image(systemName: "arrow.down.app"))").foregroundStyle(.secondary) + Text("\(data.downloads)")
                        Text("\(Image(systemName: data.downloadsPercentageChange < 0 ? "arrow.down.forward" : "arrow.up.forward"))\(percentFormatter.string(from: NSNumber(value: data.downloadsPercentageChange)) ?? "")")
                            .font(.callout)
                            .foregroundStyle(data.downloadsPercentageChange < 0 ? Color.red : Color.green)
                    }
                }
                .fontWeight(.medium)
            }
            .allowsTightening(true)
            
            if advanced || widgetFamily == .systemLarge {
                DownloadsAndProceedsChart(apps: data.apps, iconLength: 22)
                    .chartLegend(.hidden)
            } else {
                DownloadsIconsGraphic(apps: data.apps)
            }
        }
        .containerBackground(Color(UIColor.systemBackground), for: .widget)
    }
}

