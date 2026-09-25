import SwiftUI
import Charts

struct DownloadsAndProceedsChart: View {

    /// In the order their bars stand; the chart shows as many from the front as its width fits.
    let apps: [AppPerformanceSummary]
    let iconLength: CGFloat
    /// Each app's average daily active devices, keyed by Apple ID; `nil` leaves their bars out.
    var activeDevices: [String: Int]?

    var body: some View {
        GeometryReader { proxy in
            chart(apps: Array(apps.prefix(fittingCount(width: proxy.size.width))))
        }
    }

    /// Each app wants a little more than its icon's width beneath its bars; the rest of the width
    /// goes to the y-axis labels.
    private func fittingCount(width: CGFloat) -> Int {
        max(1, Int((width - 40) / (iconLength + 16)))
    }

    private func chart(apps: [AppPerformanceSummary]) -> some View {
        Chart {
            ForEach(apps) { app in
                bar(for: app, series: "Downloads", value: Double(app.downloads))
                bar(for: app, series: "Proceeds", value: app.proceeds)
                if let activeDevices {
                    bar(for: app, series: "Daily Active Devices", value: Double(activeDevices[app.appleID] ?? 0))
                }
            }
        }
        // The same colours as the home screen's figures above the chart, which stand in for its legend.
        .chartForegroundStyleScale([
            "Downloads": Color.blue,
            "Proceeds": Color.green,
            "Daily Active Devices": Color.orange
        ])
        .chartXAxis {
            AxisMarks(values: apps.map { $0.name }) { axis in
                AxisValueLabel {
                    AppIconView(app: apps[axis.index], length: iconLength)
                }
            }
        }
    }

    private func bar(for app: AppPerformanceSummary, series: String, value: Double) -> some ChartContent {
        BarMark(x: .value("App", app.name), y: .value(series, value))
            .foregroundStyle(by: .value("Data Type", series))
            .position(by: .value("Data Type", series))
    }
}
