import SwiftUI
import AuthenticationServices

struct AccountsList: View {

    @AppStorage(UserDefaults.Key.includeRedownloads, store: UserDefaults.shared) var includeRedownloads: Bool = false
    @AppStorage(UserDefaults.Key.homeSelectedKey, store: UserDefaults.shared) private var keyID: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountManager.self) var accountManager
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var assistants = AIAssistants.shared
    @State private var connectingAssistant: AIAssistant?

    @State private var googleAnalytics = GoogleAnalytics.shared
    @State private var googleAnalyticsError: Error?

    @State private var adMob = AdMob.shared
    @State private var adMobError: Error?

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

                if accountManager.accounts.count > 1 {
                    Picker("Current Account", selection: currentAccount) {
                        ForEach(accountManager.accounts) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                }

                Button("Sign In to App Store Connect", systemImage: "plus") {
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

            if showsGoogleAnalytics {
                Section("Web Analytics") {
                    ForEach(googleAnalytics.accounts) { account in
                        NavigationLink(destination: GoogleAnalyticsWebsitesView(account: account)) {
                            LabeledContent {
                                Text(googleAnalytics.websites(of: account).map(\.name).formatted(.list(type: .and)))
                            } label: {
                                Label(account.email, systemImage: "chart.bar.xaxis")
                            }
                        }
                        .contextMenu {
                            Button("Sign Out", systemImage: "xmark", role: .destructive) {
                                googleAnalytics.disconnect(account)
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { googleAnalytics.accounts[$0] }.forEach(googleAnalytics.disconnect)
                    }

                    Button("Sign In to Google Analytics", systemImage: "plus") {
                        Task { await connectGoogleAnalytics() }
                    }

                    if let googleAnalyticsError {
                        Text(googleAnalyticsError.localizedDescription)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if showsAdMob {
                Section {
                    ForEach(adMob.accounts) { account in
                        Label(account.email, systemImage: "rectangle.stack.badge.play")
                            .contextMenu {
                                Button("Sign Out", systemImage: "xmark", role: .destructive) {
                                    adMob.disconnect(account)
                                }
                            }
                    }
                    .onDelete { offsets in
                        offsets.map { adMob.accounts[$0] }.forEach(adMob.disconnect)
                    }

                    Button("Sign In to AdMob", systemImage: "plus") {
                        Task { await connectAdMob() }
                    }

                    if let adMobError {
                        Text(adMobError.localizedDescription)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Ads")
                } footer: {
                    Text("Estimated ad earnings count toward proceeds.")
                }
            }

            Section("AI Assistants") {
                ForEach(assistants.connected) { assistant in
                    Label(assistant.name, systemImage: assistant.systemImage)
                        .contextMenu {
                            Button("Sign Out", systemImage: "xmark", role: .destructive) {
                                assistants.disconnect(assistant)
                            }
                        }
                }
                .onDelete { offsets in
                    offsets.map { assistants.connected[$0] }.forEach(assistants.disconnect)
                }

                ForEach(AIAssistant.allCases.filter { !assistants.connected.contains($0) }) { assistant in
                    Button("Sign In to \(assistant.name)", systemImage: "plus") {
                        connectingAssistant = assistant
                    }
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

    /// The account the home screen shows, which is the first one until the reader picks another.
    private var currentAccount: Binding<String> {
        Binding {
            accountManager.getApiKey(apiKeyId: keyID)?.id ?? accountManager.accounts.first?.id ?? ""
        } set: {
            keyID = $0
        }
    }

    // Google services enrich App Store Connect data, so they wait for an account — unless one is already signed in, to keep its sign-out reachable.
    private var showsGoogleAnalytics: Bool {
        GoogleSignIn.isAvailable && (!accountManager.accounts.isEmpty || googleAnalytics.isConnected)
    }

    private var showsAdMob: Bool {
        GoogleSignIn.isAvailable && (!accountManager.accounts.isEmpty || adMob.isConnected)
    }

    private func connectGoogleAnalytics() async {
        googleAnalyticsError = nil
        let request = GoogleAnalytics.signInRequest()
        do {
            let callback = try await webAuthenticationSession.authenticate(using: request.url, callback: .customScheme(GoogleSignIn.callbackScheme), additionalHeaderFields: [:])
            try await googleAnalytics.connect(callback: callback, verifier: request.verifier)
        } catch ASWebAuthenticationSessionError.canceledLogin {
            return
        } catch {
            googleAnalyticsError = error
        }
    }

    private func connectAdMob() async {
        adMobError = nil
        let request = AdMob.signInRequest()
        do {
            let callback = try await webAuthenticationSession.authenticate(using: request.url, callback: .customScheme(GoogleSignIn.callbackScheme), additionalHeaderFields: [:])
            try await adMob.connect(callback: callback, verifier: request.verifier)
        } catch ASWebAuthenticationSessionError.canceledLogin {
            return
        } catch {
            adMobError = error
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
                status = APIError(err)
            }
            loading = false
        }
    }
}

/// Which of one Google account's Analytics properties are websites the reader writes about their apps on.
private struct GoogleAnalyticsWebsitesView: View {

    let account: GoogleAccount

    @Environment(\.dismiss) private var dismiss
    @State private var googleAnalytics = GoogleAnalytics.shared
    @State private var properties: [GoogleAnalyticsProperty]?
    @State private var error: Error?

    var body: some View {
        List {
            if let properties {
                ForEach(Dictionary(grouping: properties, by: \.accountName).sorted { $0.key < $1.key }, id: \.key) { accountName, properties in
                    Section(accountName) {
                        ForEach(properties) { property in
                            let isChosen = googleAnalytics.websites(of: account).contains { $0.id == property.id }
                            Button {
                                googleAnalytics.setWebsite(property, isChosen: !isChosen, of: account)
                            } label: {
                                LabeledContent(property.name) {
                                    if isChosen {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if let error {
                Text(error.localizedDescription)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    googleAnalytics.disconnect(account)
                    dismiss()
                }
            }
        }
        .navigationTitle(account.email)
        .task {
            do {
                properties = try await googleAnalytics.properties(of: account)
            } catch {
                self.error = error
            }
        }
    }
}
