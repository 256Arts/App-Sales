//
//  SettingsView.swift
//  AC Widget by NO-COMMENT
//

import SwiftUI
import WidgetKit

struct SettingsView: View {
    
    @AppStorage(UserDefaultsKey.includeRedownloads, store: UserDefaults.shared) var includeRedownloads: Bool = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var apiKeysProvider: AccountProvider

    @State private var addKeySheet: Bool = false

    @State private var cachedEntries: Int = 0

    @State private var updateSheetVisible = false

    var body: some View {
        Form {
            Section("Accounts") {
                ForEach(apiKeysProvider.accounts) { key in
                    NavigationLink(destination: AccountDetailView(key),
                                   label: {
                        HStack {
                            Text(key.name)
                            Spacer()
                            ApiKeyCheckIndicator(key: key)
                        }
                    })
                }
                .onDelete(perform: deleteKey)

                Button {
                    addKeySheet.toggle()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .contextMenu {
                    if apiKeysProvider.getApiKey(apiKeyId: "demo") == nil {
                        Button("Add Demo Account") {
                            try? apiKeysProvider.addApiKey(apiKey: Account.demoAccount)
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
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $addKeySheet) {
            NavigationStack {
                NewAccountView()
            }
        }
    }

    private func deleteKey(at offsets: IndexSet) {
        let keys = offsets.map({ apiKeysProvider.accounts[$0] })
        keys.forEach { ACDataCache.clearCache(apiKey: $0) }
        apiKeysProvider.deleteApiKeys(keys: keys)
    }
}

#Preview {
    SettingsView()
}

// MARK: - ApiKeyCheckIndicator

struct ApiKeyCheckIndicator: View {
    let key: Account
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
        .task(priority: .background, {
            do {
                try await key.checkKey()
            } catch let err {
                status = (err as? APIError) ?? .unknown
            }
            loading = false
        })
    }
}
