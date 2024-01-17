//
//  AccountManager.swift
//  App Sales
//
//  Created by Jayden Irwin on 2024-01-16.
//

import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif
import KeychainAccess

final class AccountManager: ObservableObject {
    @Published private(set) var accounts: [Account]

    init() {
        do {
            guard let data = try AccountManager.keychain.getData(AccountManager.keychainKey), !data.isEmpty else {
                accounts = []
                return
            }
            accounts = try AccountManager.getKeysFromData(data)
        } catch {
            print(error.localizedDescription)
            accounts = []
            #if DEBUG
//            fatalError(error.localizedDescription)
            #endif
        }
    }

    static let shared = AccountManager()
    private static let keychain = Keychain(service: "com.jaydenirwin.appsales")
        .synchronizable(true)
    private static let keychainKey = "ac-api-key"

    static private func getKeysFromData(_ data: Data) throws -> [Account] {
        let keys = try JSONDecoder().decode([Account].self, from: data)
        return keys.map(\.id).compactMap({ keyId in keys.first(where: { $0.id == keyId }) })
    }

    func getApiKey(apiKeyId: String) -> Account? {
        return accounts.first(where: { $0.id == apiKeyId })
    }

    /// Saves APIKey to UserDefaults; Replaces any key with same id (PrivateKeyId)
    /// - Parameter apiKey: new or updated APIKey
    func addApiKey(apiKey: Account) throws {
        accounts.removeAll(where: { $0.id == apiKey.id })
        accounts.append(apiKey)
        let encoded = try JSONEncoder().encode(accounts)
        try AccountManager.keychain.set(encoded, key: AccountManager.keychainKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    @discardableResult
    func deleteApiKey(apiKey: Account) -> Bool {
        accounts.removeAll(where: { $0.id == apiKey.id })
        do {
            let encoded = try JSONEncoder().encode(accounts)
            try AccountManager.keychain.set(encoded, key: AccountManager.keychainKey)
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func deleteApiKeys(keys: [Account]) -> Bool {
        accounts.removeAll(where: { del in
            return keys.contains(where: { other in
                return del.id == other.id
            })
        })
        do {
            let encoded = try JSONEncoder().encode(accounts)
            try AccountManager.keychain.set(encoded, key: AccountManager.keychainKey)
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
            return true
        } catch {
            return false
        }
    }
}
