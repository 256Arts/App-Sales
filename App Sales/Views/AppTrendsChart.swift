import SwiftUI
import Charts

/// One stat from the home screen's chart, day by day, with a line for each app: what the bar chart
/// becomes when its legend picks a stat.
struct AppTrendsChart: View {

    /// Best first; each draws its own line, in the chart's palette, named in the legend beneath.
    let trends: [AppTrend]
    let stat: AppListSort
    let range: Range<Date>

    var body: some View {
        Chart(trends) { trend in
            ForEach(trend.days, id: \.date) { day in
                LineMark(x: .value("Day", day.date, unit: .day), y: .value(stat.title, day.value))
                    .foregroundStyle(by: .value("App", trend.app.name))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: range.lowerBound...range.upperBound)
        .chartLegend(position: .bottom, alignment: .leading)
    }
}

struct AppTrend: Identifiable {
    let app: AppPerformanceSummary
    let days: [DailyValue]

    var id: String { app.appleID }
}
