import SwiftUI
import Charts

/// Everything App Sales knows about one app: its sales over the last 30 days and the devices they
/// came from, its webpage's views, and its App Store analytics.
struct AppDetailView: View {

    let app: AppPerformanceSummary
    let data: ACData
    let websiteTraffic: WebPageTraffic?
    /// Whether Google Analytics is connected, so the webpage can be set before it has any views.
    let showsWebsite: Bool
    let analytics: AnalyticsAvailability?

    @State private var editingWebsitePage: AppPerformanceSummary?

    /// The same 30 days as the home screen's downloads and proceeds.
    private let range = (Calendar.autoupdatingCurrent.date(byAdding: .day, value: -30, to: .now) ?? .now)..<Date.now

    private var acApps: [ACApp] {
        data.apps.filter { $0.appleID == app.appleID }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    AppIconView(app: app, length: 64)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name)
                            .font(.title2.bold())
                        Text(priceString)
                            .foregroundStyle(.secondary)
                    }
                }

                Link(destination: app.url) {
                    Label("View on the App Store", image: "logo.appstore")
                }
            }

            Section {
                Chart(dailyDownloads, id: \.date) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Downloads", day.downloads))
                }
                .chartXScale(domain: range.lowerBound...range.upperBound)
                .frame(height: 160)
                .accessibilityLabel("Downloads by day")

                LabeledContent {
                    Text(app.downloads, format: .number)
                } label: {
                    Label("Downloads", systemImage: "arrow.down.app")
                }
                LabeledContent {
                    Text(NumberFormatter.currency.string(from: NSNumber(value: app.proceeds)) ?? "")
                } label: {
                    Label("Proceeds", systemImage: "dollarsign.circle")
                }
                LabeledContent {
                    Text(Int(data.getTotal(for: .updates, in: range, filteredApps: acApps)), format: .number)
                } label: {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                LabeledContent {
                    Text(Int(data.getTotal(for: .iap, in: range, filteredApps: acApps)), format: .number)
                } label: {
                    Label("In-App Purchases", systemImage: "cart")
                }
            } header: {
                Text("Last 30 Days")
            }

            if !devices.isEmpty {
                Section("Downloads by Device") {
                    ForEach(devices, id: \.device) { row in
                        LabeledContent {
                            Text(row.downloads, format: .number)
                        } label: {
                            Label(row.device.name, systemImage: row.device.symbol)
                        }
                    }
                }
            }

            if showsWebsite {
                Section("Webpage") {
                    LabeledContent {
                        if let views = websiteTraffic?.views {
                            Text(views, format: .number)
                        } else {
                            Text("—")
                                .accessibilityLabel("Not available")
                        }
                    } label: {
                        Label("Page Views", systemImage: "globe")
                    }
                    if let url = websiteTraffic?.url {
                        Link(destination: url) {
                            Label("Open Webpage", systemImage: "safari")
                        }
                    }
                    Button("Set Webpage…", systemImage: "pencil") {
                        editingWebsitePage = app
                    }
                }
            }

            if case .ready(let analytics) = analytics {
                Section {
                    AnalyticsTotalsRows(totals: analytics.totals(for: app.appleID), downloads: Int(data.getTotal(for: .downloads, in: analytics.range, filteredApps: acApps)))
                } header: {
                    Text("App Store Analytics")
                } footer: {
                    Text("30 days through \(analytics.range.upperBound.addingTimeInterval(-1), format: .dateTime.month().day()), the latest reported.")
                }
            }
        }
        .navigationTitle(app.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .websitePageEditor(for: $editingWebsitePage, currentURL: websiteTraffic?.url)
    }

    private var priceString: String {
        guard app.price > 0 else { return String(localized: "Free") }

        return NumberFormatter.currency.string(from: NSNumber(value: app.price)) ?? ""
    }

    private var dailyDownloads: [(date: Date, downloads: Int)] {
        data.getRawData(for: .downloads, startDate: range.lowerBound, endDate: range.upperBound, filteredApps: acApps)
            .map { (date: $0.1, downloads: Int($0.0)) }
    }

    /// Most downloads first, with the report's device names folded into the ones App Sales knows.
    private var devices: [(device: ACDevice, downloads: Int)] {
        let byDevice = Dictionary(data.getDevices(.downloads, lastNDays: 30, filteredApps: acApps).map { (ACDevice($0.0), Int($0.1)) }, uniquingKeysWith: +)

        return byDevice
            .filter { $0.value > 0 }
            .map { (device: $0.key, downloads: $0.value) }
            .sorted { $0.downloads > $1.downloads }
    }
}

#Preview {
    NavigationStack {
        AppDetailView(app: ACData.example.getAppSummaries()[0], data: .example, websiteTraffic: nil, showsWebsite: false, analytics: .ready(.example(for: .example)))
    }
}
