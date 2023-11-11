//
//  SummarySmall.swift
//  AC Widget by NO-COMMENT
//

import SwiftUI
import WidgetKit

struct SummarySmall: View {
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

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                Text("App Sales")
                    .font(.headline)
                Text("30 days")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Text(currencyFormatter.string(from: NSNumber(value: data.proceeds)) ?? "")
                    .layoutPriority(999)
                Image(systemName: "arrowtriangle" + (data.proceedsPercentageChange < 0 ? ".down" : ".up"))
                    .symbolVariant(.fill)
                    .imageScale(.small)
                    .foregroundStyle(data.proceedsPercentageChange < 0 ? Color.red : Color.green)
            }
            .fontWeight(.medium)
            
            HStack(spacing: 4) {
                (Text("\(Image(systemName: "arrow.down.app"))").foregroundStyle(.secondary) + Text("\(data.downloads)"))
                    .layoutPriority(999)
                Image(systemName: "arrowtriangle" + (data.downloadsPercentageChange < 0 ? ".down" : ".up"))
                    .symbolVariant(.fill)
                    .imageScale(.small)
                    .foregroundStyle(data.downloadsPercentageChange < 0 ? Color.red : Color.green)
            }
            .fontWeight(.medium)
            
            if advanced {
                Spacer()
                
                HStack {
                    Image(systemName: "chart.bar.xaxis.ascending")
                        .scaleEffect(x: -1, y: 1)
                        .foregroundStyle(.secondary)
                    
                    ForEach(data.apps.prefix(3)) { app in
                        Group {
                            if let path = app.cachedIconURL?.path(), let data = FileManager.default.contents(atPath: path), let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                            } else {
                                Color.secondary
                            }
                        }
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(UIColor.systemFill))
                                .padding(-0.5)
                        }
                    }
                }
            }
        }
        .allowsTightening(true)
        .frame(idealWidth: .infinity, maxWidth: .infinity, alignment: .leading)
        .containerBackground(Color(UIColor.systemBackground), for: .widget)
    }
}

