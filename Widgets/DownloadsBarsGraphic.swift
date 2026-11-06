import SwiftUI
import AppSalesKit

/// The Simple widget's graph: each of the most downloaded apps, its icon beside a bar.
struct DownloadsBarsGraphic: View {

    let apps: [AppPerformanceSummary]

    private static let iconSpacing: CGFloat = 8
    private static let rowSpacing: CGFloat = 6

    private var rows: [AppPerformanceSummary] {
        Array(apps.sorted { $0.downloads > $1.downloads }.prefix(DownloadsAndProceedsChart.limit))
    }

    var body: some View {
        let rows = rows
        let best = max(1, rows.first?.downloads ?? 1)
        GeometryReader { geometry in
            let gaps = Self.rowSpacing * CGFloat(max(0, rows.count - 1))
            let rowHeight = min(32, (geometry.size.height - gaps) / CGFloat(max(1, rows.count)))
            let barRoom = geometry.size.width - rowHeight - Self.iconSpacing
            VStack(spacing: Self.rowSpacing) {
                ForEach(rows) { app in
                    HStack(spacing: Self.iconSpacing) {
                        AppIconView(app: app, length: rowHeight)
                        Capsule()
                            .fill(.blue)
                            .widgetAccentable()
                            .frame(width: max(rowHeight / 2, barRoom * CGFloat(app.downloads) / CGFloat(best)), height: rowHeight / 2)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(app.name)
                    .accessibilityValue(Text(app.downloads, format: .number))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}
