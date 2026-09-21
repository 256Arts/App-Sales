import SwiftUI
import AuthenticationServices

struct AccountsList: View {

    @AppStorage(UserDefaults.Key.includeRedownloads, store: UserDefaults.shared) var includeRedownloads: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountManager.self) var accountManager
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var assistants = AIAssistants.shared
    @State private var connectingAssistant: AIAssistant?

    @State private var googleAnalytics = GoogleAnalytics.shared
    @State private var googleAnalyticsProperties: [GoogleAnalyticsProperty] = []
    @State private var googleAnalyticsError: Error?

    @State private var showingAddAccount: Bool = false
    @State private var cachedEntries: Int = 0
    @State private var updateSheetVisible = false

    var body: some View {
        List {
            Section("App Store Connect") {
                ForEach(accountManager.accounts) { account in
                    NavigationLink(destination: AccountDetailView(account)) {
                        LabeledContent(account.name) {
                            AccountStatusSymbol(account: account)
                        }
                    }
                }
                .onDelete(perform: deleteKey)

                Button("Add", systemImage: "plus") {
                    showingAddAccount.toggle()
                }
                .contextMenu {
                    if accountManager.getApiKey(apiKeyId: "demo") == nil {
                        Button("Add Demo Account") {
                            try? accountManager.addApiKey(apiKey: Account.demoAccount)
                        }
                    }
                }
            }

            Section {
                ForEach(assistants.connected) { assistant in
                    Label(assistant.name, systemImage: assistant.systemImage)
                        .contextMenu {
                            Button("Disconnect", systemImage: "xmark", role: .destructive) {
                                assistants.disconnect(assistant)
                            }
                        }
                }
                .onDelete { offsets in
                    offsets.map { assistants.connected[$0] }.forEach(assistants.disconnect)
                }

                ForEach(AIAssistant.allCases.filter { !assistants.connected.contains($0) }) { assistant in
                    Button("Connect \(assistant.name)", systemImage: "plus") {
                        connectingAssistant = assistant
                    }
                }
            } header: {
                Text("AI Assistants")
            } footer: {
                Text("Shows how much of each assistant's limits you have left, on the home screen, in widgets, and on Apple Watch.")
            }

            if GoogleAnalytics.isAvailable {
                Section {
                    if googleAnalytics.isConnected {
                        googleAnalyticsPropertyPicker

                        Button("Disconnect", systemImage: "xmark", role: .destructive) {
                            googleAnalytics.disconnect()
                            googleAnalyticsProperties = []
                        }
                    } else {
                        Button("Connect Google Analytics", systemImage: "plus") {
                            Task { await connectGoogleAnalytics() }
                        }
                    }

                    if let googleAnalyticsError {
                        Text(googleAnalyticsError.localizedDescription)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Google Analytics")
                } footer: {
                    Text("Shows how many people read about each app on your website, beside its downloads, on the home screen.")
                }
                .task(id: googleAnalytics.isConnected) {
                    await loadGoogleAnalyticsProperties()
                }
            }

//            Section {
//                Toggle("INCLUDE_REDOWNLOADS", isOn: $includeRedownloads)
//                Text("Cached entries: \(cachedEntries)")
//                    .onAppear {
//                        self.cachedEntries = ACDataCache.numberOfEntriesCached()
//                    }
//
//                Button("Clear cache", role: .destructive) {
//                    AppStoreConnectAPI.clearMemoization()
//                    Account.clearMemoization()
//                    ACDataCache.clearCache()
//                    self.cachedEntries = ACDataCache.numberOfEntriesCached()
//                }
//            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            NavigationStack {
                NewAccountView()
            }
        }
        .sheet(item: $connectingAssistant) { assistant in
            AIUsageSignInSheet(assistant: assistant)
        }
    }

    /// Which of the reader's Google Analytics properties is the website they write about their apps on.
    @ViewBuilder
    private var googleAnalyticsPropertyPicker: some View {
        Picker("Website", selection: Binding(get: { googleAnalytics.property }, set: { $0.map(googleAnalytics.setProperty) })) {
            if googleAnalytics.property == nil {
                Text("Choose…").tag(GoogleAnalyticsProperty?.none)
            }
            ForEach(googleAnalyticsProperties) { property in
                Text("\(property.name) (\(property.accountName))").tag(Optional(property))
            }
        }
    }

    private func connectGoogleAnalytics() async {
        googleAnalyticsError = nil
        let request = GoogleAnalytics.signInRequest()
        do {
            let callback = try await webAuthenticationSession.authenticate(using: request.url, callback: .customScheme(GoogleAnalytics.callbackScheme), additionalHeaderFields: [:])
            try await googleAnalytics.connect(callback: callback, verifier: request.verifier)
        } catch ASWebAuthenticationSessionError.canceledLogin {
            return
        } catch {
            googleAnalyticsError = error
        }
    }

    private func loadGoogleAnalyticsProperties() async {
        guard googleAnalytics.isConnected else { return }

        do {
            googleAnalyticsProperties = try await googleAnalytics.properties()
        } catch {
            googleAnalyticsError = error
        }
    }

    private func deleteKey(at offsets: IndexSet) {
        let keys = offsets.map({ accountManager.accounts[$0] })
        keys.forEach { ACDataCache.clearCache(apiKey: $0) }
        accountManager.deleteApiKeys(keys: keys)
    }
}

#Preview {
    AccountsList()
}

// MARK: - AccountStatusSymbol

struct AccountStatusSymbol: View {
    let account: Account
    @State private var status: APIError?
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                Image(systemName: "icloud")
                    .foregroundStyle(.gray)
            } else if status == nil {
                Image(systemName: "checkmark.icloud")
                    .foregroundStyle(.green)
            } else if status == .invalidCredentials {
                Image(systemName: "xmark.icloud")
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "exclamationmark.icloud")
                    .foregroundStyle(.orange)
            }
        }
        .task(priority: .background) {
            do {
                try await account.checkKey()
            } catch let err {
                status = (err as? APIError) ?? .unknown
            }
            loading = false
        }
    }
}
