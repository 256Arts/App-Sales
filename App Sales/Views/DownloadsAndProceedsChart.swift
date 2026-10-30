import SwiftUI
import Charts

struct DownloadsAndProceedsChart: View {

    /// In the order their bars stand, top down: the first `limit` get a row each, and the rest share
    /// an Other row beneath them — unless there is only one more, which takes the row itself.
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
        let shown = apps.count == Self.limit + 1 ? apps.count : Self.limit
        var rows = apps.prefix(shown).map { app in
            Row(id: app.appleID, app: app, downloads: Double(app.downloads), proceeds: app.proceeds, activeDevices: Double(activeDevices?[app.appleID] ?? 0))
        }
        let rest = apps.dropFirst(shown)
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
        // The axis only holds the icons' room: Charts sets a categorical label on its band's top
        // edge whatever its anchor, so the icons are laid in the overlay, across each band's middle.
        .chartYAxis {
            AxisMarks(preset: .extended, position: .leading, values: rows.map(\.id)) { axis in
                AxisValueLabel(horizontalSpacing: Self.iconSpacing) {
                    Color.clear
                        .frame(width: iconLength, height: iconLength)
                        .accessibilityLabel(rows[axis.index].app?.name ?? String(localized: "Other"))
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    ForEach(rows) { row in
                        if let y = proxy.position(forY: row.id) {
                            icon(for: row)
                                .position(x: frame.minX - Self.iconSpacing - iconLength / 2, y: frame.minY + y)
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }

    private static let iconSpacing: CGFloat = 8

    @ViewBuilder
    private func icon(for row: Row) -> some View {
        if let app = row.app {
            AppIconView(app: app, length: iconLength)
        } else {
            Image(systemName: "app.grid.2x2.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: iconLength, height: iconLength)
        }
    }

    private func bar(for row: Row, series: String, value: Double) -> some ChartContent {
        BarMark(x: .value(series, value), y: .value("App", row.id))
            .foregroundStyle(by: .value("Data Type", series))
            .position(by: .value("Data Type", series))
    }
}
