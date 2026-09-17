import SwiftUI

struct HomeView: View {
    
    @State var loader = SalesDataLoader()

    @State var showingAccountsList = false

    @Environment(AccountManager.self) var accountManager

    @AppStorage(UserDefaults.Key.homeSelectedKey, store: UserDefaults.shared) private var keyID: String = ""
    @AppStorage(UserDefaults.Key.appListSort, store: UserDefaults.shared) private var appListSort: AppListSort = .downloads
    
    private var selectedKey: Account? {
        return accountManager.getApiKey(apiKeyId: keyID) ?? accountManager.accounts.first
    }
    private let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.negativePrefix = ""
        return formatter
    }()
    private var appListIconLength: CGFloat {
        #if os(macOS)
        24
        #else
        32
        #endif
    }

    private var refreshButton: some View {
        Button("Refresh", systemImage: "arrow.clockwise") {
            Task { await fetchData(useMemoization: false) }
        }
    }
    private var accountsButton: some View {
        Button("Accounts", systemImage: "person.crop.circle") {
            showingAccountsList.toggle()
        }
    }

    var body: some View {
        Group {
            if accountManager.accounts.isEmpty {
                Text("No Account")
                    .foregroundStyle(.secondary)
            } else if let data = loader.data {
                List {
                    Section {
                        VStack(alignment: .leading) {
                            if let summary = loader.summary {
                                HStack {
                                    Text(NumberFormatter.currency.string(from: NSNumber(value: summary.proceeds)) ?? "")
                                        // The screenshot walk waits on this before its first shot,
                                        // so a capture cannot beat the fetched data onto the screen.
                                        .accessibilityIdentifier("Summary.Proceeds")
                                    Text("\(Image(systemName: summary.proceedsPercentageChange < 0 ? "arrow.down.forward" : "arrow.up.forward"))\(percentFormatter.string(from: NSNumber(value: summary.proceedsPercentageChange)) ?? "")")
                                        .foregroundStyle(summary.proceedsPercentageChange < 0 ? Color.red : Color.green)
                                }
                                
                                HStack {
                                    Text("\(Text(Image(systemName: "arrow.down.app")).foregroundStyle(.secondary))\(summary.downloads)")
                                    Text("\(Image(systemName: summary.downloadsPercentageChange < 0 ? "arrow.down.forward" : "arrow.up.forward"))\(percentFormatter.string(from: NSNumber(value: summary.downloadsPercentageChange)) ?? "")")
                                        .foregroundStyle(summary.downloadsPercentageChange < 0 ? Color.red : Color.green)
                                }
                                
                                DownloadsAndProceedsChart(apps: summary.topApps, iconLength: 32)
                                    #if os(visionOS)
                                    .frame(height: 300)
                                    #else
                                    .frame(height: 400)
                                    #endif
                            }
                        }
                        .font(.title)
                        .padding(.vertical)
                    } footer: {
                        TimelineView(.everyMinute) { context in
                            Text(updatedDateString(lastRefreshDate: data.latestReportingDate()))
                        }
                    }

                    if let summary = loader.summary {
                        InsightsView(summary: summary)

                        if let selectedKey {
                            AppStoreAnalyticsSection(account: selectedKey, data: data, apps: summary.apps)
                        }

                        WebsiteTrafficSection(apps: summary.apps)

                        Section {
                            ForEach(appListSort.sort(summary.apps)) { app in
                                AppRow(app: app, iconLength: appListIconLength)
                            }
                        } header: {
                            HStack {
                                Text("Apps")

                                Spacer()

                                Menu {
                                    Picker("Sort By", selection: $appListSort) {
                                        ForEach(AppListSort.allCases) { sort in
                                            Label(sort.title, systemImage: sort.systemImage)
                                                .tag(sort)
                                        }
                                    }
                                } label: {
                                    Label("Sort By", systemImage: "arrow.up.arrow.down")
                                        .labelStyle(.iconOnly)
                                }
                                .menuIndicator(.hidden)
                            }
                        }

                        AIUsageSection()
                    }
                }
                .refreshable {
                    await fetchData(useMemoization: false)
                }
            } else if let error = loader.error {
                VStack(spacing: 20) {
                    Text(error.localizedDescription)
                        .foregroundStyle(.secondary)
                    
                    Button("Retry") {
                        Task { await fetchData(useMemoization: false) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("App Sales")
        .toolbar {
            // Refresh stays in the bar under space pressure, overflowing last.
            #if os(visionOS)
            ToolbarItem(placement: .primaryAction) {
                refreshButton
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                refreshButton
            }
            .visibilityPriority(.high)
            #endif

            #if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                accountsButton
            }
            #else
            ToolbarItem(placement: .topBarPinnedTrailing) {
                accountsButton
            }
            ToolbarOverflowMenu {
                AppSalesApp.links()
            }
            #endif
        }
        .sheet(isPresented: $showingAccountsList) {
            NavigationStack {
                AccountsList()
            }
            #if os(macOS)
            .frame(idealHeight: 400)
            #endif
        }
        .onChange(of: keyID) {
            Task { await fetchData(useMemoization: false) }
        }
        .task { await fetchData(useMemoization: true) }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await fetchData() }
        }
        #endif
    }
    
    private let relativeDateFormatter = RelativeDateTimeFormatter()

    private func fetchData(useMemoization: Bool = true) async {
        await loader.load(account: selectedKey, useMemoization: useMemoization)
    }
    
    private func updatedDateString(lastRefreshDate: Date) -> String {
        guard lastRefreshDate != .distantPast else { return "" }
        
        let string: String
        if Date.now.timeIntervalSince(lastRefreshDate) < 60 {
            string = "Just Now"
        } else {
            string = relativeDateFormatter.localizedString(for: lastRefreshDate, relativeTo: .now)
        }
        return "Updated \(string)"
    }
}

/// One app in the home screen's app list: its icon, its 30-day downloads and proceeds, its price,
/// and a link to its App Store page.
private struct AppRow: View {

    let app: AppPerformanceSummary
    let iconLength: CGFloat

    var body: some View {
        HStack {
            AppIconView(app: app, length: iconLength)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)

                HStack(spacing: 8) {
                    downloads
                    proceeds
                    price
                    // Soaks up the width the row has spare, so the three stay grouped
                    // at the leading edge rather than spreading across the row.
                    Spacer(minLength: 0)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            Spacer()

            Link(destination: app.url) {
                Image("logo.appstore")
            }
            .accessibilityLabel("View \(app.name) on the App Store")
        }
    }

    /// Downloads and proceeds are both over the last 30 days, matching the summary above the list.
    private var downloads: some View {
        Label(app.downloads.formatted(), systemImage: "arrow.down.app")
            .accessibilityLabel("\(app.downloads) downloads in the last 30 days")
    }
    /// Bare, the way the summary above the list prints its total: the currency symbol says enough.
    private var proceeds: some View {
        Text(proceedsString)
            .accessibilityLabel("\(proceedsString) proceeds in the last 30 days")
    }
    private var price: some View {
        Label(priceString, systemImage: "tag")
            .accessibilityLabel("Priced at \(priceString)")
    }

    private var proceedsString: String {
        NumberFormatter.currency.string(from: NSNumber(value: app.proceeds)) ?? ""
    }
    private var priceString: String {
        guard app.price > 0 else { return String(localized: "Free") }

        return NumberFormatter.currency.string(from: NSNumber(value: app.price)) ?? ""
    }
}

#Preview {
    HomeView(loader: SalesDataLoader(data: .example))
}
