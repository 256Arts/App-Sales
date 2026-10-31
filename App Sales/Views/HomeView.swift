import SwiftUI
import AppSalesKit
import AIUsageKit
#if canImport(AdmobSwiftUI)
import AdmobSwiftUI
#endif

struct HomeView: View {
    
    @State var loader = SalesDataLoader()

    @State var showingAccountsList = false
    @State private var aiAssistants = AIAssistants.shared
    @State private var editingWebsitePage: AppPerformanceSummary?
    @State private var selection: HomeSelection? = .summary
    /// The summary, on a phone: the app list is one step back from it, the way Mail opens on the inbox.
    @State private var preferredColumn = NavigationSplitViewColumn.detail

    #if canImport(AdmobSwiftUI)
    @StateObject private var nativeAdViewModel = NativeAdViewModel(adUnitID: "ca-app-pub-8282547272443688/5107419575")
    #endif

    @Environment(AccountManager.self) var accountManager

    @AppStorage(UserDefaults.Key.homeSelectedKey, store: UserDefaults.shared) private var keyID: String = ""
    @AppStorage(UserDefaults.Key.appListSort, store: UserDefaults.shared) private var appListSort: AppListSort = .downloads
    /// The stats hidden from the app rows, as comma-separated `AppListSort` raw values.
    @AppStorage(UserDefaults.Key.appListHiddenStats, store: UserDefaults.shared) private var hiddenStatsValue = AppListOptions.defaultHiddenStats
    
    private var selectedKey: Account? {
        return accountManager.getApiKey(apiKeyId: keyID) ?? accountManager.accounts.first
    }
    private var appListIconLength: CGFloat {
        #if os(macOS)
        32
        #else
        40
        #endif
    }

    private var hiddenStats: Set<AppListSort> {
        AppListOptions.hiddenStats(in: hiddenStatsValue)
    }

    private var accountsButton: some View {
        Button("Accounts", systemImage: "person.crop.circle") {
            showingAccountsList.toggle()
        }
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 400)
        } detail: {
            switch selection ?? .summary {
            case .summary:
                summaryView
            case .app(let appleID):
                if let app = loader.summary?.apps.first(where: { $0.appleID == appleID }) {
                    AppDetailView(app: app, loader: loader) {
                        AppReviewsSection(account: selectedKey, appleID: appleID)
                    }
                    .id(appleID)
                } else {
                    ProgressView()
                }
            }
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
        .websitePageEditor(for: $editingWebsitePage, currentURL: editingWebsitePage.flatMap { loader.websiteTraffic[$0.appleID]?.url })
        .loadsSales(loader, account: selectedKey)
        .onChange(of: keyID) {
            selection = .summary
        }
        .focusedSceneValue(\.homeCommands, HomeCommandContext(
            countedStats: loader.summary.map { _ in Set(loader.appCounts.keys) },
            refresh: { Task { await loader.refresh() } },
            showAccounts: { showingAccountsList = true }))
    }

    /// The summary, then every app, each opening its own screen beside the list.
    private var sidebar: some View {
        List(selection: $selection) {
            NavigationLink(value: HomeSelection.summary) {
                Label("Summary", systemImage: "chart.bar.xaxis")
            }

            if let summary = loader.summary {
                let counts = loader.appCounts
                ForEach(appListSort.sort(summary.apps, counts: counts[appListSort] ?? [:])) { app in
                    NavigationLink(value: HomeSelection.app(app.appleID)) {
                        AppRow(app: app, iconLength: appListIconLength, counts: counts, hiddenStats: hiddenStats)
                    }
                    .contextMenu {
                        Link(destination: app.url) {
                            Label("View on the App Store", image: "logo.appstore")
                        }
                        if loader.showsWebsite {
                            if let url = loader.websiteTraffic[app.appleID]?.url {
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
        }
        .refreshable { await loader.refresh() }
        .navigationTitle("App Sales")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                #if os(macOS)
                if loader.summary != nil {
                    viewOptionsMenu(counts: loader.appCounts)
                }
                #else
                viewOptionsMenu(counts: loader.summary.map { _ in loader.appCounts })
                #endif
                accountsButton
            }
        }
    }

    /// Which stats the app rows show, and what they are sorted by, above the 256 Arts links (which
    /// the Mac keeps in its Help menu). A stat without figures yet is left out of both, unless it is
    /// the chosen sort, so the menu still shows what the list is in.
    private func viewOptionsMenu(counts: [AppListSort: [String: Int]]?) -> some View {
        Menu {
            if let counts {
                AppListOptions(countedStats: Set(counts.keys))
            }
            #if !os(macOS)
            Section {
                AppSalesApp.links()
            }
            #endif
        } label: {
            Label("View Options", systemImage: "ellipsis")
        }
        .menuIndicator(.hidden)
    }

    private var summaryView: some View {
        Group {
            if accountManager.accounts.isEmpty {
                Text("No Account")
                    .foregroundStyle(.secondary)
            } else if loader.data != nil {
                List {
                    SalesSummarySection(loader: loader)
                    SharePiesSection(loader: loader)
                    FunnelSection(loader: loader)
                    InsightsView(loader: loader)

                    #if canImport(AdmobSwiftUI)
                    if ExperienceManager.shared.shouldShowAds {
                        Section {
                            NativeAdView(nativeViewModel: nativeAdViewModel, style: .banner)
                                .frame(height: 100)
                                .listRowInsets(.all, 0)
                                .onAppear {
                                    nativeAdViewModel.refreshAd()
                                }
                        }
                    }
                    #endif

                    AIUsageSection(refreshCount: loader.refreshCount, placeholder: Text("Sign in to Claude or Codex in Accounts to see how much of each one's limits you have left, beside the day's sales."))
                }
                .refreshable { await loader.refresh() }
            } else if let error = loader.error {
                VStack(spacing: 20) {
                    Text(error.localizedDescription)
                        .foregroundStyle(.secondary)
                    
                    Button("Retry") {
                        Task { await loader.load(account: selectedKey, useMemoization: false) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Summary")
    }
}

/// What the focused window's home screen offers the menu bar's commands.
struct HomeCommandContext {
    /// Nil until the sales have loaded, which is when there is a list to sort.
    let countedStats: Set<AppListSort>?
    let refresh: () -> Void
    let showAccounts: () -> Void
}

extension FocusedValues {
    @Entry var homeCommands: HomeCommandContext?
}

/// What the sidebar has chosen: the summary, or one app by its Apple ID.
private enum HomeSelection: Hashable {
    case summary
    case app(String)
}

#Preview {
    HomeView(loader: SalesDataLoader(data: .example, lastRefresh: .now))
}
