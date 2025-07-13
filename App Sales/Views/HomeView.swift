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

    @AppStorage(UserDefaults.Key.whatsNewVersion) var whatsNewVersion = 0
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
        #if targetEnvironment(macCatalyst)
        24
        #else
        32
        #endif
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
                                    Text("\(Image(systemName: "arrow.down.app"))").foregroundStyle(.secondary) + Text("\(summary.downloads)")
                                    Text("\(Image(systemName: summary.downloadsPercentageChange < 0 ? "arrow.down.forward" : "arrow.up.forward"))\(percentFormatter.string(from: NSNumber(value: summary.downloadsPercentageChange)) ?? "")")
                                        .foregroundStyle(summary.downloadsPercentageChange < 0 ? Color.red : Color.green)
                                }
                                
                                DownloadsAndProceedsChart(apps: summary.apps, iconLength: 32)
                                    .frame(height: 400)
                            }
                        }
                        .font(.title)
                        .padding(.vertical)
                    } footer: {
                        TimelineView(.everyMinute) { context in
                            Text(updatedDateString(lastRefreshDate: data.latestReportingDate()))
                        }
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
        #if !os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                Button("Accounts", systemImage: "person.crop.circle") {
                    showingAccountsList.toggle()
                }
                
                Section {
                    Link(destination: URL(string: "https://www.256arts.com/")!) {
                        Label("Developer Website", systemImage: "safari")
                    }
                    Link(destination: URL(string: "https://www.256arts.com/joincommunity/")!) {
                        Label("Join Community", systemImage: "bubble.left.and.bubble.right")
                    }
                    Link(destination: URL(string: "https://github.com/256Arts/App-Sales")!) {
                        Label("Contribute on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
        }
        #endif
        .sheet(isPresented: $showingAccountsList) {
            NavigationStack {
                AccountsList()
            }
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
