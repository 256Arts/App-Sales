import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif
import KeychainAccess

@Observable
final class AccountManager {
    private(set) var accounts: [Account]

    init() {
        // A screenshot run gets its accounts handed to it and never touches the real Keychain: the
        // machine taking the shots has live App Store Connect credentials in there.
        if ScreenshotMode.isActive {
            accounts = ScreenshotMode.accounts
            return
        }
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

    /// Saves APIKey to the Keychain; Replaces any key with same id (PrivateKeyId)
    /// - Parameter apiKey: new or updated APIKey
    func addApiKey(apiKey: Account) throws {
        accounts.removeAll(where: { $0.id == apiKey.id })
        accounts.append(apiKey)
        try persist()
    }

    @discardableResult
    func deleteApiKey(apiKey: Account) -> Bool {
        deleteApiKeys(keys: [apiKey])
    }

    @discardableResult
    func deleteApiKeys(keys: [Account]) -> Bool {
        accounts.removeAll(where: { account in
            keys.contains(where: { $0.id == account.id })
        })
        do {
            try persist()
            return true
        } catch {
            return false
        }
    }

    /// Writes the accounts back to the Keychain and tells the widgets to refetch.
    private func persist() throws {
        // A screenshot run's accounts live in memory only; writing them would put demo credentials
        // into the machine's real, iCloud-synchronized Keychain.
        guard !ScreenshotMode.isActive else { return }

        let encoded = try JSONEncoder().encode(accounts)
        try AccountManager.keychain.set(encoded, key: AccountManager.keychainKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
