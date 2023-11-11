//
//  Account.swift
//  AC Widget by NO-COMMENT
//

import Foundation
import UIKit
import SwiftUI
import WidgetKit
import KeychainAccess
import AppIntents

final class AccountProvider: ObservableObject {
    @Published private(set) var accounts: [Account]

    init() {
        do {
            guard let data = try AccountProvider.keychain.getData(AccountProvider.keychainKey), !data.isEmpty else {
                accounts = []
                return
            }
            accounts = try AccountProvider.getKeysFromData(data)
        } catch {
            print(error.localizedDescription)
            accounts = []
            #if DEBUG
//            fatalError(error.localizedDescription)
            #endif
        }
    }

    static let shared = AccountProvider()
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
        try AccountProvider.keychain.set(encoded, key: AccountProvider.keychainKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    @discardableResult
    func deleteApiKey(apiKey: Account) -> Bool {
        accounts.removeAll(where: { $0.id == apiKey.id })
        do {
            let encoded = try JSONEncoder().encode(accounts)
            try AccountProvider.keychain.set(encoded, key: AccountProvider.keychainKey)
            WidgetCenter.shared.reloadAllTimelines()
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
            try AccountProvider.keychain.set(encoded, key: AccountProvider.keychainKey)
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch {
            return false
        }
    }
}

struct Account: Codable, Identifiable, Hashable, AppEntity {
    var id: String { privateKeyID }
    let name: String
    let issuerID: String
    let privateKeyID: String
    let privateKey: String
    let vendorNumber: String

    init(name: String, issuerID: String, privateKeyID: String, privateKey: String, vendorNumber: String) {
        self.name = name
        self.issuerID = issuerID
        self.privateKeyID = privateKeyID
        self.vendorNumber = vendorNumber

        self.privateKey = privateKey
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .removeCharacters(from: .whitespacesAndNewlines)
    }
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static var defaultQuery = AccountQuery()
    
    static let demoAccount = Account(name: "Demo", issuerID: "demo", privateKeyID: "demo", privateKey: "demo", vendorNumber: "demo")
            
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct AccountQuery: EntityQuery {
    func entities(for identifiers: [Account.ID]) async throws -> [Account] {
        AccountProvider.shared.accounts.filter { identifiers.contains($0.id) }
    }
    
    func suggestedEntities() async throws -> [Account] {
        AccountProvider.shared.accounts
    }
    
    func defaultResult() async -> Account? {
        try? await suggestedEntities().first
    }
}

extension Account {
    func equalsKeyDetails(other key: Account) -> Bool {
        return self.issuerID == key.issuerID && self.privateKeyID == key.privateKeyID && self.privateKey == key.privateKey && self.privateKeyID == key.privateKeyID
    }
}

@MainActor
extension Account {
    static private var lastChecks: [Account: LoaderStatus] = [:]
    private enum LoaderStatus {
        case inProgress(Task<Void, Error>)
        case loaded((error: Error?, date: Date))
    }

    static func clearMemoization() {
        lastChecks.removeAll()
    }

    func checkKey() async throws {
        if let check = Account.lastChecks[self] {
            switch check {
            case .loaded(let res):
                if res.date.timeIntervalSinceNow > -30 {
                    if let error = res.error {
                        throw error
                    } else {
                        return
                    }
                } else {
                    Account.lastChecks.removeValue(forKey: self)
                }
            case .inProgress(let task):
                try await task.value
                return
            }
        }

        let task: Task<Void, Error> = Task {
            let api = AppStoreConnectAPI(apiKey: self)
            do {
                _ = try await api.getData(numOfDays: 1, useCache: false)
            } catch APIError.noDataAvailable {
                return
            } catch let error as APIError {
                throw error
            } catch {
                throw APIError.unknown
            }
            return
        }

        Account.lastChecks[self] = .inProgress(task)

        do {
            try await task.value
            Account.lastChecks[self] = .loaded((error: nil, date: .now))
        } catch {
            Account.lastChecks[self] = .loaded((error: error, date: .now))
            throw error
        }

        return
    }
}
