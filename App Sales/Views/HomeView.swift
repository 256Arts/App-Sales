//
//  HomeView.swift
//  AC Widget by NO-COMMENT
//

import SwiftUI
import AppStoreConnect_Swift_SDK
#if canImport(WidgetKit)
import WidgetKit
#endif

struct HomeView: View {
    
    @State var data: ACData?
    @State var error: APIError?

    @State var showingAccountsList = false

    @Environment(AccountManager.self) var accountManager

    @AppStorage(UserDefaults.Key.homeSelectedKey, store: UserDefaults.shared) private var keyID: String = ""
    
    private var selectedKey: Account? {
        return accountManager.getApiKey(apiKeyId: keyID) ?? accountManager.accounts.first
    }
    private var summary: PerformanceSummary? {
        data?.getPerformanceSummary()
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
            } else if let data {
                List {
                    Section {
                        VStack(alignment: .leading) {
                            if let summary {
                                HStack {
                                    Text(currencyFormatter.string(from: NSNumber(value: summary.proceeds)) ?? "")
                                    Text("\(Image(systemName: summary.proceedsPercentageChange < 0 ? "arrow.down.forward" : "arrow.up.forward"))\(percentFormatter.string(from: NSNumber(value: summary.proceedsPercentageChange)) ?? "")")
                                        .foregroundStyle(summary.proceedsPercentageChange < 0 ? Color.red : Color.green)
                                }
                                
                                HStack {
                                    Text("\(Text(Image(systemName: "arrow.down.app")).foregroundStyle(.secondary))\(summary.downloads)")
                                    Text("\(Image(systemName: summary.downloadsPercentageChange < 0 ? "arrow.down.forward" : "arrow.up.forward"))\(percentFormatter.string(from: NSNumber(value: summary.downloadsPercentageChange)) ?? "")")
                                        .foregroundStyle(summary.downloadsPercentageChange < 0 ? Color.red : Color.green)
                                }
                                
                                DownloadsAndProceedsChart(apps: summary.apps, iconLength: 32)
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

                    if let summary {
                        InsightsView(summary: summary)
                    }

                    Section {
                        ForEach(data.apps) { app in
                            HStack {
                                AsyncImage(url: app.iconURL100) { image in
                                    image
                                        .resizable()
                                        .clipShape(RoundedRectangle(cornerRadius: appListIconLength / 4))
                                } placeholder: {
                                    Color.secondary
                                        .clipShape(RoundedRectangle(cornerRadius: appListIconLength / 4))
                                }
                                .frame(width: appListIconLength, height: appListIconLength)
                                
                                VStack(alignment: .leading) {
                                    Text(app.name)
                                    if let price = currencyFormatter.string(from: NSNumber(value: app.price)) {
                                        Text(price)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Link(destination: app.url) {
                                    Image("logo.appstore")
                                }
                            }
                        }
                    }
                }
                .refreshable {
                    await fetchData(useMemoization: false)
                }
            } else if let error {
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
    private let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
//        formatter.currencyCode =
        return formatter
    }()

    private func fetchData(useMemoization: Bool = true) async {
        guard let apiKey = selectedKey else { return }
        let api = AppStoreConnectAPI(apiKey: apiKey)
        do {
            self.data = try await api.getData(currency: Currency(rawValue: Locale.autoupdatingCurrent.currency?.identifier ?? ""), useMemoization: useMemoization)
            self.error = nil
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch let err as APIError {
            self.data = nil
            self.error = err
        } catch { }
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

#Preview {
    HomeView(data: ACData.example)
}
