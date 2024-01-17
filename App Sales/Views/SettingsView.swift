//
//  SettingsView.swift
//  AC Widget by NO-COMMENT
//

import SwiftUI

struct SettingsView: View {
    
    @AppStorage(UserDefaults.Key.includeRedownloads, store: UserDefaults.shared) var includeRedownloads: Bool = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var accountManager: AccountManager

    @State private var showingAddAccount: Bool = false
    @State private var cachedEntries: Int = 0
    @State private var updateSheetVisible = false
    #if os(macOS)
    @State private var selectedAccount: Account?
    #endif

    var body: some View {
        Form {
            Section("Accounts") {
                ForEach(accountManager.accounts) { account in
                    #if os(macOS)
                    Button {
                        selectedAccount = account
                    } label: {
                        LabeledContent(account.name) {
                            AccountStatusSymbol(account: account)
                        }
                    }
                    #else
                    NavigationLink(destination: AccountDetailView(account)) {
                        LabeledContent(account.name) {
                            AccountStatusSymbol(account: account)
                        }
                    }
                    #endif
                }
                .onDelete(perform: deleteKey)

                Button {
                    showingAddAccount.toggle()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .contextMenu {
                    if accountManager.getApiKey(apiKeyId: "demo") == nil {
                        Button("Add Demo Account") {
                            try? accountManager.addApiKey(apiKey: Account.demoAccount)
                        }
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
        .navigationTitle("Settings")
        #if os(macOS)
        .sheet(isPresented: Binding(get: {
            selectedAccount != nil
        }, set: { newValue in
            if !newValue {
                selectedAccount = nil
            }
        })) {
            if let selectedAccount {
                NavigationStack {
                    AccountDetailView(selectedAccount)
                        .scenePadding()
                }
            }
        }
        #else
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        #endif
        .sheet(isPresented: $showingAddAccount) {
            NavigationStack {
                NewAccountView()
            }
        }
    }

    private func deleteKey(at offsets: IndexSet) {
        let keys = offsets.map({ accountManager.accounts[$0] })
        keys.forEach { ACDataCache.clearCache(apiKey: $0) }
        accountManager.deleteApiKeys(keys: keys)
    }
}

#Preview {
    SettingsView()
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
                    .foregroundColor(.gray)
            } else if status == nil {
                Image(systemName: "checkmark.icloud")
                    .foregroundColor(.green)
            } else if status == .invalidCredentials {
                Image(systemName: "xmark.icloud")
                    .foregroundColor(.red)
            } else {
                Image(systemName: "exclamationmark.icloud")
                    .foregroundColor(.orange)
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
