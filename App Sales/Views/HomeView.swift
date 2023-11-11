//
//  HomeView.swift
//  AC Widget by NO-COMMENT
//

import SwiftUI
import AppStoreConnect_Swift_SDK

struct HomeView: View {
    
    @State var data: ACData?
    @State var error: APIError?

    @State var showSettings = false

    @EnvironmentObject var apiKeysProvider: AccountProvider

    @AppStorage(UserDefaultsKey.homeSelectedKey, store: UserDefaults.shared) private var keyID: String = ""
    private var selectedKey: Account? {
        return apiKeysProvider.getApiKey(apiKeyId: keyID) ?? apiKeysProvider.accounts.first
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

    var body: some View {
        Group {
            if apiKeysProvider.accounts.isEmpty {
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
                                        .aspectRatio(contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                } placeholder: {
                                    Color.secondary
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .frame(height: 32)
                                
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
                    await onAppear(useMemoization: false)
                }
            } else if let error {
                Text(error.localizedDescription)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("App Sales")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showSettings.toggle()
                }, label: {
                    Image(systemName: "gear")
                })
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .onChange(of: keyID, perform: { _ in Task { await onAppear(useMemoization: false) } })
        .task { await onAppear(useMemoization: true) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await onAppear() }
        }
    }
    
    private let relativeDateFormatter = RelativeDateTimeFormatter()
    private let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
//        formatter.currencyCode =
        return formatter
    }()

    private func onAppear(useMemoization: Bool = true) async {
        guard let apiKey = selectedKey else { return }
        let api = AppStoreConnectAPI(apiKey: apiKey)
        do {
            self.data = try await api.getData(currency: Currency(rawValue: Locale.autoupdatingCurrent.currency?.identifier ?? ""), useMemoization: useMemoization)
            self.error = nil
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
