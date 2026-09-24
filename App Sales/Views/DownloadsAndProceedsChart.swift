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
                    AppIconView(app: apps[axis.index], length: iconLength)
                }
            }
        }
    }
}

//#Preview {
//    DownloadsAndProceedsChart(apps:)
//}
