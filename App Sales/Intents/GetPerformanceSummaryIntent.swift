import AppIntents
import Foundation

/// "How much did my apps make today?" — one metric's total for a period, the change against the
/// window before it, and the per-app breakdown as a snippet.
struct GetPerformanceSummaryIntent: AppIntent {

    static var title: LocalizedStringResource = "Get Sales Summary"
    static var description = IntentDescription(
        "Reports proceeds, downloads, updates, or in-app purchases for an App Store Connect account.",
        categoryName: "Sales",
        resultValueName: "Total")

    @Parameter(title: "Account")
    var account: Account?

    @Parameter(title: "Metric", default: .proceeds)
    var metric: InfoType

    @Parameter(title: "Period", default: .last30Days)
    var period: SalesPeriod

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$metric) for \(\.$period)") {
            \.$account
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog & ShowsSnippetView {
        let data = try await SalesIntentData.data(for: account)

        let total = data.getTotal(for: metric, in: period.dateRange)
        let previous = data.getTotal(for: metric, in: period.previousDateRange)
        let change = PerformanceSummary.percentageChange(from: previous, to: total)
        let apps = data.getAppSummaries(in: period.dateRange)

        return .result(
            value: total,
            dialog: dialog(total: total, previous: previous, change: change, currency: data.displayCurrency),
            view: SalesSummarySnippet(
                metric: metric,
                period: period,
                total: total,
                change: change,
                apps: apps,
                currency: data.displayCurrency))
    }

    /// A sentence Siri can read out on its own, without the snippet.
    private func dialog(total: Double, previous: Double, change: Double, currency: Currency) -> IntentDialog {
        let value = metric.format(total, currency: currency)
        let percentage = abs(change).formatted(.percent.precision(.fractionLength(0)))

        guard previous > 0 else {
            return IntentDialog("\(metric.title), \(period.title): \(value).")
        }

        let direction = change < 0 ? String(localized: "down") : String(localized: "up")
        return IntentDialog("\(metric.title), \(period.title): \(value), \(direction) \(percentage) from the period before.")
    }
}
