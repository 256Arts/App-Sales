//
//  AccountsList.swift
//  AC Widget by NO-COMMENT
//

import SwiftUI

struct AccountsList: View {
    
    @AppStorage(UserDefaults.Key.includeRedownloads, store: UserDefaults.shared) var includeRedownloads: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountManager.self) var accountManager

    @State private var showingAddAccount: Bool = false
    @State private var cachedEntries: Int = 0
    @State private var updateSheetVisible = false

    var body: some View {
        List {
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
