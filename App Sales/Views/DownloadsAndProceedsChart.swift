import SwiftUI
import Charts

struct DownloadsAndProceedsChart: View {

    /// In the order their bars stand, top down: the first `limit` get a row each, and the rest share
    /// an Other row beneath them.
    let apps: [AppPerformanceSummary]
    let iconLength: CGFloat
    /// Each app's average daily active devices, keyed by Apple ID; `nil` leaves their bars out.
    var activeDevices: [String: Int]?

    static let limit = 4

    private struct Row: Identifiable {
        let id: String
        let app: AppPerformanceSummary?
        let downloads: Double
        let proceeds: Double
        let activeDevices: Double
    }

    private var rows: [Row] {
        var rows = apps.prefix(Self.limit).map { app in
            Row(id: app.appleID, app: app, downloads: Double(app.downloads), proceeds: app.proceeds, activeDevices: Double(activeDevices?[app.appleID] ?? 0))
        }
        let rest = apps.dropFirst(Self.limit)
        if !rest.isEmpty {
            rows.append(Row(
                id: "Other",
                app: nil,
                downloads: Double(rest.reduce(0) { $0 + $1.downloads }),
                proceeds: rest.reduce(0) { $0 + $1.proceeds },
                activeDevices: Double(rest.reduce(0) { $0 + (activeDevices?[$1.appleID] ?? 0) })))
        }
        return rows
    }

    var body: some View {
        let rows = rows
        Chart {
            ForEach(rows) { row in
                bar(for: row, series: "Downloads", value: row.downloads)
                bar(for: row, series: "Proceeds", value: row.proceeds)
                if activeDevices != nil {
                    bar(for: row, series: "Daily Active Devices", value: row.activeDevices)
                }
            }
        }
        // The same colours as the home screen's figures above the chart, which stand in for its legend.
        .chartForegroundStyleScale([
            "Downloads": Color.blue,
            "Proceeds": Color.green,
            "Daily Active Devices": Color.orange
        ])
        .chartYScale(domain: rows.map(\.id))
        .chartYAxis {
            AxisMarks(preset: .extended, position: .leading, values: rows.map(\.id)) { axis in
                AxisValueLabel(centered: true) {
                    if let app = rows[axis.index].app {
                        AppIconView(app: app, length: iconLength)
                    } else {
                        // Where an icon would be, so Other lines up with the apps above it.
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .frame(width: iconLength, height: iconLength)
                            .background(.fill.secondary, in: .rect(cornerRadius: iconLength / 4))
                            .accessibilityLabel("Other")
                    }
                }
            }
        }
    }

    private func bar(for row: Row, series: String, value: Double) -> some ChartContent {
        BarMark(x: .value(series, value), y: .value("App", row.id))
            .foregroundStyle(by: .value("Data Type", series))
            .position(by: .value("Data Type", series))
    }
}
