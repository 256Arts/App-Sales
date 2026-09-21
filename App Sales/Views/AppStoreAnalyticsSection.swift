import SwiftUI

/// The home screen's App Store analytics: how many people saw the apps and their product pages,
/// how many of them downloaded, and how many are using the apps.
struct AppStoreAnalyticsSection: View {

    let account: Account
    let data: ACData
    let apps: [AppPerformanceSummary]
    /// Held by the home screen, whose app rows show each app's product page views.
    @Binding var availability: AnalyticsAvailability?

    @State private var error: Error?
    @State private var loadedAt: Date?

    var body: some View {
        Section {
            switch availability {
            case .ready(let analytics):
                AnalyticsTotalsRows(totals: analytics.totals(), downloads: downloads(in: analytics.range))

                NavigationLink {
                    AppStoreAnalyticsByAppView(analytics: analytics, data: data, apps: apps)
                } label: {
                    Label("By App", systemImage: "square.grid.2x2")
                }
            case .preparing:
                Text("App Store Connect is preparing analytics reports for your apps. The first ones usually arrive within two days.")
                    .foregroundStyle(.secondary)
            case .needsAdminKey:
                Text("Analytics reports need to be turned on once with an API key that has the Admin role. After that, a Sales and Reports key can read them.")
                    .foregroundStyle(.secondary)
            case nil:
                if let error {
                    Text(error.localizedDescription)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
        } header: {
            Label("App Store Analytics", systemImage: "chart.bar.xaxis")
        } footer: {
            if case .ready(let analytics) = availability {
                Text("30 days through \(analytics.range.upperBound.addingTimeInterval(-1), format: .dateTime.month().day()), the latest reported.")
            }
        }
        .task(id: account.id) {
            await load()
        }
    }

    private func downloads(in range: Range<Date>) -> Int {
        Int(data.getTotal(for: .downloads, in: range))
    }

    private func load() async {
        // Coming back from the per-app screen reappears the section; the reports only change daily.
        if let loadedAt, availability != nil, loadedAt.timeIntervalSinceNow > -5 * 60 { return }

        error = nil
        do {
            availability = try await AnalyticsReportsAPI(account: account).getAnalytics(appleIDs: data.apps.map(\.appleID), sales: data)
            loadedAt = .now
        } catch {
            availability = nil
            self.error = error
        }
    }
}

/// Every app's analytics, most-viewed first, so page views can be read against downloads app by app.
private struct AppStoreAnalyticsByAppView: View {

    let analytics: AppStoreAnalytics
    let data: ACData
    let apps: [AppPerformanceSummary]

    private var rows: [(app: AppPerformanceSummary, totals: AnalyticsTotals)] {
        apps
            .map { ($0, analytics.totals(for: $0.appleID)) }
            .sorted { $0.totals.pageViews > $1.totals.pageViews }
    }

    var body: some View {
        List {
            ForEach(rows, id: \.app.id) { row in
                Section {
                    AnalyticsTotalsRows(totals: row.totals, downloads: downloads(of: row.app))
                } header: {
                    Label {
                        Text(row.app.name)
                    } icon: {
                        AppIconView(app: row.app, length: 20)
                    }
                }
            }
        }
        .navigationTitle("App Store Analytics")
    }

    private func downloads(of app: AppPerformanceSummary) -> Int {
        guard let acApp = data.apps.first(where: { $0.appleID == app.appleID }) else { return 0 }

        return Int(data.getTotal(for: .downloads, in: analytics.range, filteredApps: [acApp]))
    }
}

/// The funnel from being seen to being used, as one row per figure.
private struct AnalyticsTotalsRows: View {

    let totals: AnalyticsTotals
    let downloads: Int

    var body: some View {
        LabeledContent {
            Text(totals.impressions, format: .number)
        } label: {
            Label("Impressions", systemImage: "eye")
        }
        LabeledContent {
            Text(totals.pageViews, format: .number)
        } label: {
            Label("Product Page Views", systemImage: "doc.text.magnifyingglass")
        }
        LabeledContent {
            Text(downloads, format: .number)
        } label: {
            Label("Downloads", systemImage: "arrow.down.app")
        }
        LabeledContent {
            if let rate = totals.conversionRate(downloads: downloads) {
                Text(rate, format: .percent.precision(.fractionLength(0...1)))
            } else {
                Text("—")
                    .accessibilityLabel("Not available")
            }
        } label: {
            Label("Conversion Rate", systemImage: "percent")
        }
        LabeledContent {
            Text(totals.sessions, format: .number)
        } label: {
            Label("Sessions", systemImage: "hand.tap")
        }
        LabeledContent {
            Text(totals.averageDailyActiveDevices, format: .number)
        } label: {
            Label("Daily Active Devices", systemImage: "person.2")
        }
    }
}
