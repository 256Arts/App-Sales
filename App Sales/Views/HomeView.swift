import SwiftUI

struct HomeView: View {
    
    @State var loader = SalesDataLoader()

    @State var showingAccountsList = false
    @State private var googleAnalytics = GoogleAnalytics.shared
    @State private var aiAssistants = AIAssistants.shared
    /// Keyed by Apple ID; empty while Google Analytics is not connected.
    @State private var websiteTraffic: [String: WebPageTraffic] = [:]
    @State private var editingWebsitePage: AppPerformanceSummary?
    @State private var appStoreAnalytics: AnalyticsAvailability?
    /// What `appStoreAnalytics` was last loaded for, and when, since the reports only change daily.
    @State private var appStoreAnalyticsLoad: (query: AppStoreAnalyticsQuery, date: Date)?
    /// Counts pulls to refresh, so the AI usage below the sales refreshes along with them.
    @State private var refreshCount = 0

    @Environment(AccountManager.self) var accountManager

    @AppStorage(UserDefaults.Key.homeSelectedKey, store: UserDefaults.shared) private var keyID: String = ""
    @AppStorage(UserDefaults.Key.appListSort, store: UserDefaults.shared) private var appListSort: AppListSort = .downloads
    @AppStorage(UserDefaults.Key.homeChartSort, store: UserDefaults.shared) private var chartSortChoice: AppListSort = .downloads
    @AppStorage(UserDefaults.Key.homeChartShowsActiveDevices, store: UserDefaults.shared) private var chartShowsActiveDevices = false
    
    private var selectedKey: Account? {
        return accountManager.getApiKey(apiKeyId: keyID) ?? accountManager.accounts.first
    }
    private var appListIconLength: CGFloat {
        #if os(macOS)
        24
        #else
        32
        #endif
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
                        if let summary = loader.summary {
                            let availableActiveDevices = appCounts(of: summary.apps)[.activeDevices]
                            let activeDevices = chartShowsActiveDevices ? availableActiveDevices : nil
                            VStack(alignment: .leading, spacing: 16) {
                                // In the chart's order, each figure's icon in its bars' colour, so the row doubles as the legend.
                                HStack(alignment: .top, spacing: 16) {
                                    SummaryStat(
                                        name: "Downloads",
                                        value: summary.downloads.formatted(),
                                        systemImage: "arrow.down.app",
                                        color: .blue,
                                        change: summary.downloadsPercentageChange)
                                    SummaryStat(
                                        name: "Proceeds",
                                        value: NumberFormatter.currency.string(from: NSNumber(value: summary.proceeds)) ?? "",
                                        systemImage: "dollarsign.circle",
                                        color: .green,
                                        change: summary.proceedsPercentageChange,
                                        // The screenshot walk waits on this before its first shot,
                                        // so a capture cannot beat the fetched data onto the screen.
                                        identifier: "Summary.Proceeds")
                                    if let activeDevices {
                                        let total = summary.apps.reduce(0) { $0 + (activeDevices[$1.appleID] ?? 0) }
                                        SummaryStat(
                                            name: AppListSort.activeDevices.title,
                                            value: total.formatted(),
                                            systemImage: AppListSort.activeDevices.systemImage,
                                            color: .orange,
                                            caption: "a day")
                                    }

                                    Spacer(minLength: 0)

                                    chartMenu(activeDevicesAvailable: availableActiveDevices != nil)
                                }

                                DownloadsAndProceedsChart(
                                    apps: chartSort(activeDevices: activeDevices).sort(summary.apps, counts: activeDevices ?? [:]),
                                    iconLength: 32,
                                    activeDevices: activeDevices)
                                    .chartLegend(.hidden)
                                    #if os(visionOS)
                                    .frame(height: 300)
                                    #else
                                    .frame(height: 400)
                                    #endif
                            }
                            .padding(.vertical)
                        }
                    } footer: {
                        // Two ages, and they are not the same one: when App Sales last asked, and
                        // how far the reports it was given reach — App Store Connect publishes a
                        // day behind, so the second is always older than it looks.
                        HStack(spacing: 4) {
                            if let lastRefresh = loader.lastRefresh {
                                Text(updated: lastRefresh)

                                if data.latestReportingDate() != .distantPast {
                                    Text(verbatim: "·")
                                }
                            }

                            if data.latestReportingDate() != .distantPast {
                                Text("Sales through \(data.latestReportingDate(), format: .dateTime.month().day())")
                            }
                        }
                    }

                    if let summary = loader.summary {
                        InsightsView(summary: summary)

                        let counts = appCounts(of: summary.apps)
                        Section {
                            ForEach(appListSort.sort(summary.apps, counts: counts[appListSort] ?? [:])) { app in
                                Group {
                                    if app.isOnAppStore {
                                        NavigationLink {
                                            AppDetailView(
                                                app: app,
                                                data: data,
                                                websiteTraffic: websiteTraffic[app.appleID],
                                                showsWebsite: googleAnalytics.property != nil,
                                                analytics: appStoreAnalytics)
                                        } label: {
                                            AppRow(app: app, iconLength: appListIconLength, counts: counts)
                                        }
                                    } else {
                                        AppRow(app: app, iconLength: appListIconLength, counts: counts)
                                    }
                                }
                                .contextMenu {
                                    // Nothing to open for an app no longer on the App Store.
                                    if app.isOnAppStore {
                                        Link(destination: app.url) {
                                            Label("View on the App Store", image: "logo.appstore")
                                        }
                                        if googleAnalytics.property != nil {
                                            if let url = websiteTraffic[app.appleID]?.url {
                                                Link(destination: url) {
                                                    Label("Open Webpage", systemImage: "safari")
                                                }
                                            }
                                            Button("Set Webpage…", systemImage: "pencil") {
                                                editingWebsitePage = app
                                            }
                                        }
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text("Apps")

                                Spacer()

                                Menu {
                                    Picker("Sort By", selection: $appListSort) {
                                        ForEach(AppListSort.allCases.filter { !$0.sortsByCounts || counts[$0] != nil || $0 == appListSort }) { sort in
                                            Label(sort.title, systemImage: sort.systemImage)
                                                .tag(sort)
                                        }
                                    }
                                    .pickerStyle(.inline)
                                } label: {
                                    Label("Sort By", systemImage: "arrow.up.arrow.down")
                                        .labelStyle(.iconOnly)
                                }
                                .menuIndicator(.hidden)
                            }
                        }

                        AIUsageSection(refreshCount: refreshCount)
                    }
                }
                .refreshable {
                    refreshCount += 1
                    await fetchData(useMemoization: false)
                }
                .websitePageEditor(for: $editingWebsitePage, currentURL: editingWebsitePage.flatMap { websiteTraffic[$0.appleID]?.url })
                .task(id: AppStoreAnalyticsQuery(accountID: selectedKey?.id, appIDs: data.apps.map(\.appleID))) {
                    await loadAppStoreAnalytics(data: data)
                }
                .task(id: WebsiteTrafficQuery(property: googleAnalytics.property, pageURLs: googleAnalytics.pageURLs, appIDs: loader.summary?.apps.map(\.appleID) ?? [])) {
                    await loadWebsiteTraffic()
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
        // Asked for by an AI usage row, or by the Mac's menu bar extra, whose sign-in was refused.
        .sheet(item: $aiAssistants.signingIn) { assistant in
            AIUsageSignInSheet(assistant: assistant)
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
    
    /// The figures the chart can be sorted by, in the order its bars stand.
    private static let chartSorts: [AppListSort] = [.downloads, .proceeds, .activeDevices]

    /// Downloads while the chosen sort's figures are not on the chart.
    private func chartSort(activeDevices: [String: Int]?) -> AppListSort {
        chartSortChoice == .activeDevices && activeDevices == nil ? .downloads : chartSortChoice
    }

    /// Daily active devices come from the analytics reports, so they can only be turned on once
    /// those have figures — or off, whenever they are on.
    private func chartMenu(activeDevicesAvailable: Bool) -> some View {
        Menu {
            Toggle(isOn: $chartShowsActiveDevices) {
                Label(AppListSort.activeDevices.title, systemImage: AppListSort.activeDevices.systemImage)
            }
            .disabled(!activeDevicesAvailable && !chartShowsActiveDevices)

            Picker("Sort By", selection: $chartSortChoice) {
                ForEach(Self.chartSorts.filter { $0 != .activeDevices || chartShowsActiveDevices }) { sort in
                    Label(sort.title, systemImage: sort.systemImage)
                        .tag(sort)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Chart Options", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .symbolVariant(.circle.fill)
                .symbolRenderingMode(.hierarchical)
        }
        .menuIndicator(.hidden)
        .onChange(of: chartShowsActiveDevices) {
            if !chartShowsActiveDevices, chartSortChoice == .activeDevices {
                chartSortChoice = .downloads
            }
        }
    }

    private func fetchData(useMemoization: Bool = true) async {
        await loader.load(account: selectedKey, useMemoization: useMemoization)
    }
    
    /// The figures of each `sortsByCounts` sort, keyed by Apple ID. A sort is missing until it
    /// has figures, which leaves its column out of the rows and out of the sort menu (unless it is
    /// the chosen one, so the menu still shows what the list is sorted by).
    private func appCounts(of apps: [AppPerformanceSummary]) -> [AppListSort: [String: Int]] {
        var counts: [AppListSort: [String: Int]] = [.websiteViews: websiteTraffic.mapValues(\.views)]
        if case .ready(let analytics) = appStoreAnalytics {
            let totals = Dictionary(uniqueKeysWithValues: apps.map { ($0.appleID, analytics.totals(for: $0.appleID)) })
            counts[.impressions] = totals.mapValues(\.impressions)
            counts[.appStoreViews] = totals.mapValues(\.pageViews)
            counts[.activeDevices] = totals.mapValues(\.averageDailyActiveDevices)
        }
        return counts.filter { !$0.value.isEmpty }
    }

    /// What the App Store analytics depend on, so they reload when the account or its apps change.
    private struct AppStoreAnalyticsQuery: Equatable {
        let accountID: String?
        let appIDs: [String]
    }

    private func loadAppStoreAnalytics(data: ACData) async {
        let query = AppStoreAnalyticsQuery(accountID: selectedKey?.id, appIDs: data.apps.map(\.appleID))
        // Coming back from an app's screen reappears the list; the reports only change daily.
        if let appStoreAnalyticsLoad, appStoreAnalyticsLoad.query == query, appStoreAnalyticsLoad.date.timeIntervalSinceNow > -5 * 60 { return }
        guard let selectedKey else { return }

        if appStoreAnalyticsLoad?.query.accountID != query.accountID {
            appStoreAnalytics = nil
        }
        // A failed fetch keeps the last figures rather than blanking every row.
        if let availability = try? await AnalyticsReportsAPI(account: selectedKey).getAnalytics(appleIDs: query.appIDs, sales: data) {
            appStoreAnalytics = availability
            appStoreAnalyticsLoad = (query, .now)
        }
    }

    /// What the website traffic depends on, so it reloads when the website, a page, or the apps change.
    private struct WebsiteTrafficQuery: Equatable {
        let property: GoogleAnalyticsProperty?
        let pageURLs: [String: URL]
        let appIDs: [String]
    }

    private func loadWebsiteTraffic() async {
        guard GoogleAnalytics.isAvailable, googleAnalytics.property != nil, let apps = loader.summary?.apps else {
            websiteTraffic = [:]
            return
        }

        // A failed fetch keeps the last figures rather than blanking every row.
        if let traffic = try? await googleAnalytics.traffic(for: apps.map { ($0.appleID, $0.name) }) {
            websiteTraffic = traffic
        }
    }
}

/// One app in the home screen's app list: its icon, name and price, then its figures in
/// `AppListSort` order, so they read the same way as the sort menu. An app no longer on the App
/// Store shows none of them.
private struct AppRow: View {

    let app: AppPerformanceSummary
    let iconLength: CGFloat
    /// The figures of each `sortsByCounts` sort, keyed by Apple ID, from `HomeView.appCounts(of:)`.
    let counts: [AppListSort: [String: Int]]

    var body: some View {
        HStack {
            AppIconView(app: app, length: iconLength)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(app.name)
                    if app.isOnAppStore {
                        price
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .labelStyle(StatLabelStyle())
                    }
                }
                .lineLimit(1)

                Group {
                    if app.isOnAppStore {
                        HStack(spacing: 8) {
                            ForEach(AppListSort.allCases) { sort in
                                stat(for: sort)
                            }
                            // Soaks up the width the row has spare, so the stats stay grouped
                            // at the leading edge rather than spreading across the row.
                            Spacer(minLength: 0)
                        }
                    } else {
                        Text("Not on the App Store")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .labelStyle(StatLabelStyle())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
    }

    /// The name and price sit on the line above, so they have no stat here.
    @ViewBuilder
    private func stat(for sort: AppListSort) -> some View {
        switch sort {
        case .downloads: downloads
        case .proceeds: proceeds
        case .name, .price: EmptyView()
        case .websiteViews, .impressions, .appStoreViews, .activeDevices:
            // Each column is as wide as its widest row's figure, so the stats after it line up.
            if let values = counts[sort], let widest = values.values.max() {
                ViewsColumn(views: values[app.appleID], widest: widest, systemImage: sort.systemImage) {
                    spokenLabel(for: sort, count: $0)
                }
            }
        }
    }

    private func spokenLabel(for sort: AppListSort, count: Int) -> Text {
        switch sort {
        case .impressions: Text("\(count) App Store impressions in the last 30 days")
        case .appStoreViews: Text("\(count) App Store product page views in the last 30 days")
        case .activeDevices: Text("\(count) active devices a day over the last 30 days")
        default: Text("\(count) webpage views in the last 30 days")
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

/// A view count, as wide as the widest row's figure whether or not this app has one, so the
/// column holds.
private struct ViewsColumn: View {

    let views: Int?
    let widest: Int
    let systemImage: String
    /// What VoiceOver reads for a count, since the icon alone says nothing spoken.
    let spokenLabel: (Int) -> Text

    var body: some View {
        ZStack(alignment: .leading) {
            Label(widest.formatted(), systemImage: systemImage)
                .hidden()
            if let views {
                Label(views.formatted(), systemImage: systemImage)
                    .accessibilityLabel(spokenLabel(views))
            }
        }
        .accessibilityHidden(views == nil)
    }
}

/// One figure above the home screen's chart: its icon in the colour of its bars, and beneath it
/// the change from the 30 days before, or a caption for a figure with nothing to compare against.
private struct SummaryStat: View {

    /// What VoiceOver reads for the icon.
    let name: LocalizedStringKey
    let value: String
    let systemImage: String
    let color: Color
    var change: Double?
    var caption: LocalizedStringKey?
    var identifier = ""

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.negativePrefix = ""
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .symbolVariant(.fill)
                    .foregroundStyle(color)
                    .accessibilityLabel(Text(name))
                Text(value)
            }
            .font(.title3.weight(.semibold))

            Group {
                if let change {
                    Text("\(Image(systemName: change < 0 ? "arrow.down.forward" : "arrow.up.forward"))\(Self.percentFormatter.string(from: NSNumber(value: change)) ?? "")")
                        .foregroundStyle(change < 0 ? Color.red : Color.green)
                } else if let caption {
                    Text(caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// A stat's icon hard against its figure, so the gaps in the row fall between stats instead.
private struct StatLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.icon
            configuration.title
        }
    }
}

#Preview {
    HomeView(loader: SalesDataLoader(data: .example, lastRefresh: .now))
}
