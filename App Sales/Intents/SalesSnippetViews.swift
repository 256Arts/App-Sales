import AppIntents
import SwiftUI

/// The card Siri and Shortcuts show for `GetPerformanceSummaryIntent`: one metric's total for the
/// period, how it moved against the window before it, and the apps behind it.
struct SalesSummarySnippet: View {

    let metric: InfoType
    let period: SalesPeriod
    let total: Double
    let change: Double
    let apps: [AppPerformanceSummary]
    let currency: Currency

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SnippetHeader(title: metric.title, systemImage: metric.systemImage, period: period)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metric.format(total, currency: currency))
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                ChangeLabel(change: change)
                    .font(.headline)
            }

            AppBreakdown(apps: apps, metric: metric, currency: currency)
        }
        .padding()
    }
}

/// The card for `GetAppSummariesIntent`: the per-app breakdown on its own, with no headline number.
struct AppSalesSnippet: View {

    let period: SalesPeriod
    let apps: [AppPerformanceSummary]
    let currency: Currency

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SnippetHeader(title: "Sales by App", systemImage: "square.grid.2x2", period: period)

            AppBreakdown(apps: apps, metric: .downloads, currency: currency, showsProceeds: true)
        }
        .padding()
    }
}

private struct SnippetHeader: View {

    let title: LocalizedStringResource
    let systemImage: String
    let period: SalesPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(String(localized: title), systemImage: systemImage)
                .font(.headline)
            Text(String(localized: period.title))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Up to six apps, the same handful `PerformanceSummary.topApps` gives the chart and the widget.
private struct AppBreakdown: View {

    let apps: [AppPerformanceSummary]
    let metric: InfoType
    let currency: Currency
    var showsProceeds = false

    var body: some View {
        if apps.isEmpty {
            Text("No sales in this period.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 8) {
                ForEach(apps.prefix(6)) { app in
                    HStack(spacing: 10) {
                        AppIconView(app: app, length: 28)

                        Text(app.name)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(trailingText(for: app))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .font(.subheadline)
        }
    }

    private func trailingText(for app: AppPerformanceSummary) -> String {
        let downloads = InfoType.downloads.format(Double(app.downloads), currency: currency)
        guard showsProceeds else {
            // `AppPerformanceSummary` only carries downloads and proceeds, so updates and in-app
            // purchases fall back to the downloads column rather than printing a wrong number.
            return metric == .proceeds ? InfoType.proceeds.format(app.proceeds, currency: currency) : downloads
        }

        return "\(downloads)  ·  \(InfoType.proceeds.format(app.proceeds, currency: currency))"
    }
}

/// The up/down arrow and percentage the home screen puts beside its totals.
private struct ChangeLabel: View {

    let change: Double

    var body: some View {
        Label {
            Text(abs(change).formatted(.percent.precision(.fractionLength(0))))
        } icon: {
            Image(systemName: change < 0 ? "arrow.down.forward" : "arrow.up.forward")
        }
        .foregroundStyle(change < 0 ? Color.red : Color.green)
    }
}

#Preview {
    SalesSummarySnippet(
        metric: .proceeds,
        period: .last30Days,
        total: 1234.56,
        change: 0.12,
        apps: ACData.example.getAppSummaries(),
        currency: .USD)
}
