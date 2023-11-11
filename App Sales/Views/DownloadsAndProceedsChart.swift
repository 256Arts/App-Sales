//
//  DownloadsAndProceedsChart.swift
//  App Sales
//
//  Created by 256 Arts Developer on 2023-10-26.
//

import SwiftUI
import Charts

struct DownloadsAndProceedsChart: View {
    
    let apps: [AppPerformanceSummary]
    let iconLength: CGFloat
    let daysRange = 30
    
    var body: some View {
        Chart {
            ForEach(apps) { app in
                BarMark(x: .value("App", app.name), y: .value("Downloads", app.downloads))
                    .foregroundStyle(.blue)
                    .foregroundStyle(by: .value("Data Type", "Downloads"))
                    .position(by: .value("Data Type", "Downloads"))
                
                BarMark(x: .value("App", app.name), y: .value("Proceeds", app.proceeds))
                    .foregroundStyle(.green)
                    .foregroundStyle(by: .value("Data Type", "Proceeds"))
                    .position(by: .value("Data Type", "Proceeds"))
                
            }
        }
        .chartXAxis {
            AxisMarks(values: apps.map { $0.name }) { axis in
                AxisValueLabel {
                    AsyncImage(url: apps[axis.index].iconURL) { image in
                        image.resizable()
                    } placeholder: {
                        if let path = apps[axis.index].cachedIconURL?.path(), let data = FileManager.default.contents(atPath: path), let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage).resizable()
                        } else {
                            Color.secondary
                        }
                    }
                    .frame(width: iconLength, height: iconLength)
                    .cornerRadius(iconLength / 4)
                }
            }
        }
    }
}

//#Preview {
//    DownloadsAndProceedsChart(apps:)
//}
