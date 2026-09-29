import SwiftUI

/// Picks which Keychain account the watch shows.
///
/// Deliberately read-only: an App Store Connect private key is hundreds of characters, so accounts
/// are added on the iPhone or Mac and arrive here over iCloud Keychain.
struct WatchAccountPicker: View {

    @Environment(AccountManager.self) private var accountManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage(UserDefaults.Key.homeSelectedKey, store: UserDefaults.shared) private var keyID: String = ""

    /// Falls back the same way the home screen does, so the checkmark marks the account actually
    /// on screen rather than nothing at all before a first pick.
    private var selectedID: String? {
        (accountManager.getApiKey(apiKeyId: keyID) ?? accountManager.accounts.first)?.id
    }

    var body: some View {
        List(accountManager.accounts) { account in
            Button {
                keyID = account.id
                dismiss()
            } label: {
                LabeledContent(account.name) {
                    if account.id == selectedID {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .navigationTitle("Accounts")
    }
}

#Preview {
    NavigationStack {
        WatchAccountPicker()
    }
    .environment(AccountManager.shared)
}
