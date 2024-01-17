//
//  AccountDetailView.swift
//  AC Widget by NO-COMMENT
//

import SwiftUI

struct AccountDetailView: View {
    
    @AppStorage(UserDefaults.Key.homeSelectedKey, store: UserDefaults.shared) private var keyID: String = ""
    
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var apiKeysProvider: AccountManager

    let account: Account
    @State private var keyName: String
    private var issuerID: String
    private var privateKeyID: String
    private var privateKey: String
    private var vendorNumber: String

    @State private var status: APIError?

    @State private var apps: [ACApp] = []
    @State private var cachedEntries: Int

    init(_ key: Account) {
        self.account = key
        self._keyName = State(initialValue: key.name)
        self._cachedEntries = State(initialValue: ACDataCache.numberOfEntriesCached(apiKey: key))
        self.issuerID = key.issuerID
        self.privateKeyID = key.privateKeyID
        self.privateKey = key.privateKey
        self.vendorNumber = key.vendorNumber
    }

    var body: some View {
        Form {
            Toggle(isOn: Binding(get: {
                keyID == account.id
            }, set: { newValue in
                if newValue {
                    keyID = account.id
                }
            })) {
                Text("Current")
            }
            
            Section {
                LabeledContent("Account Name") {
                    TextField("Account Name", text: $keyName)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                }

                Button("Save", action: save)
            }
            
            if let status = status {
                Section {
                    Text(status.localizedDescription)
                }
            }
            
            Section {
                LabeledContent("Issuer ID") {
                    Text(issuerID)
                        .textSelection(.enabled)
                }
                LabeledContent("Private Key ID") {
                    Text(privateKeyID)
                        .textSelection(.enabled)
                }
                LabeledContent("Private Key") {
                    HStack {
                        Text("••••\(String(privateKey.suffix(4)))")
                        Button {
                            #if canImport(UIKit)
                            UIPasteboard.general.string = privateKey
                            #else
                            NSPasteboard.general.setString(privateKey, forType: .string)
                            #endif
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
                LabeledContent("Vendor Number") {
                    Text(vendorNumber)
                        .textSelection(.enabled)
                }
            }
            
            Section {
                Button("Delete", role: .destructive) {
                    showingDeleteAlert.toggle()
                }
            }
            .alert(isPresented: $showingDeleteAlert) {
                Alert(
                    title: Text("Delete Account?"),
                    primaryButton: .destructive(Text("Delete")) {
                        ACDataCache.clearCache(apiKey: account)
                        apiKeysProvider.deleteApiKeys(keys: [account])
                        dismiss()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .task {
            do {
                try await account.checkKey()
                try await loadApps()
            } catch let err {
                status = (err as? APIError) ?? .unknown
            }
        }
        .navigationTitle("Account")
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        #endif
    }

    private func loadApps() async throws {
        let api = AppStoreConnectAPI(apiKey: account)
        let data = try await api.getData(currency: Currency.USD, useCache: true)
        self.apps = data.apps
    }

    private func save() {
        try? apiKeysProvider.addApiKey(apiKey: Account(name: keyName,
                                        issuerID: issuerID,
                                        privateKeyID: privateKeyID,
                                        privateKey: privateKey,
                                        vendorNumber: vendorNumber))
    }

    @State var showingDeleteAlert = false
}

#Preview {
    AccountDetailView(Account.demoAccount)
}
