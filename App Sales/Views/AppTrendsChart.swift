import SwiftUI
import Charts

/// One stat from the home screen's chart, day by day, stacked app by app: what the bar chart
/// becomes when its legend picks a stat.
struct AppTrendsChart: View {

    /// Best first, Other last; drawn the other way round, so the best sit atop the stack.
    let trends: [AppTrend]
    let stat: AppListSort
    let range: Range<Date>

    private static let colors: [Color] = [.blue, .green, .orange, .purple, .red]

    var body: some View {
        Chart(trends.reversed()) { trend in
            ForEach(trend.days, id: \.date) { day in
                AreaMark(x: .value("Day", day.date, unit: .day), y: .value(stat.title, day.value))
                    .foregroundStyle(by: .value("App", trend.name))
                    .interpolationMethod(.monotone)
            }
        }
        // The legend reads best first, whatever order the stack is drawn in.
        .chartForegroundStyleScale(
            domain: trends.map(\.name),
            range: trends.indices.map { $0 < Self.colors.count && !trends[$0].isOther ? Self.colors[$0] : .gray })
        .chartXScale(domain: range.lowerBound...range.upperBound)
        .chartLegend(position: .bottom, alignment: .leading)
    }
}

struct AppTrend: Identifiable {
    let id: String
    let name: String
    let days: [DailyValue]

    init(app: AppPerformanceSummary, days: [DailyValue]) {
        id = app.appleID
        name = app.name
        self.days = days
    }

    /// Every app past the chart's few, summed.
    init(otherDays days: [DailyValue]) {
        id = "Other"
        name = String(localized: "Other")
        self.days = days
    }

    var isOther: Bool { id == "Other" }
}
