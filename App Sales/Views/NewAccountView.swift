//
//  NewAccountView.swift
//  AC Widget by NO-COMMENT
//

import SwiftUI

struct NewAccountView: View {
    
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var apiKeysProvider: AccountManager
    @State private var alert: AddAPIKeyAlert?

    @State private var name: String = ""
    @State private var issuerID: String = ""
    @State private var keyID: String = ""
    @State private var key: String = ""
    @State private var vendor: String = ""

    @State private var errorFields: Set<Fields> = .init()

    var body: some View {
        ScrollView {
            VStack {
                TextField("Account Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                
                VStack {
                    Text("If you haven't created an API key yet, now is the time to do it.")
                        .multilineTextAlignment(.center)
                    
                    Link(destination: URL(string: "https://developer.apple.com/documentation/appstoreconnectapi/creating_api_keys_for_app_store_connect_api")!) {
                        HStack {
                            Text("How to create an API key")
                            Image(systemName: "arrow.up.forward.app")
                        }
                    }
                }
                .padding(.vertical)
                
                VStack {
                    HStack {
                        Text("Issuer ID")
                            .font(.headline)
                        Spacer()
                        infoCard(title: "On the top of the keys page in App Store Connect, it will state your 'Issuer ID'.")
                    }

                    TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $issuerID)
                        .modifier(TextFieldStyle(borderColor: errorFields.contains(.issuerID) ? .red : nil))
                }
                VStack {
                    HStack {
                        Text("Private Key ID")
                            .font(.headline)
                        Spacer()
                        infoCard(title: "In the third column of the table on the keys page in App Store Connect.")
                    }

                    TextField("XXXXXXXXXX", text: $keyID)
                        .modifier(TextFieldStyle(borderColor: errorFields.contains(.keyID) ? .red : nil))
                }
                VStack {
                    HStack {
                        Text("Private Key")
                            .font(.headline)
                        Spacer()
                        infoCard(title: "You should have gotten the key right after creating it. Once you close the window, there unfortunately is no way to show it again. You'll have to create a new one.")
                    }

                    TextEditor(text: $key)
                        .modifier(TextFieldStyle(borderColor: errorFields.contains(.key) ? .red : nil))
                        .frame(height: 150)
                }
                VStack {
                    HStack {
                        Text("Vendor Number")
                            .font(.headline)
                        Spacer()
                        infoCard(title: "You can find it on App Store Connect in your 'Reports' tab. In the top left it should state your 'Vendor #'.")
                    }

                    TextField("XXXXXXXX", text: $vendor)
                        .modifier(TextFieldStyle(borderColor: errorFields.contains(.vendor) ? .red : nil))
                }
            }
            .scenePadding()
        }
        .navigationTitle("New Account")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert(item: $alert, content: { generateAlert($0) })
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    if name.isEmpty || issuerID.isEmpty || keyID.isEmpty || key.isEmpty || vendor.isEmpty {
                        errorFields.removeAll()
                        if name.isEmpty { errorFields.insert(.name) }
                        if issuerID.isEmpty { errorFields.insert(.issuerID) }
                        if key.isEmpty { errorFields.insert(.key) }
                        if keyID.isEmpty { errorFields.insert(.keyID) }
                        if vendor.isEmpty { errorFields.insert(.vendor) }
                        if key.isEmpty { errorFields.insert(.key) }
                    } else {
                        onFinishPressed()
                    }
                }
                .disabled(name.isEmpty || issuerID.isEmpty || keyID.isEmpty || key.isEmpty || vendor.isEmpty)
                .onChange(of: name + issuerID + keyID + key + vendor) { errorFields.removeAll() }
            }
        }
    }

    private func onFinishPressed() {
        let apiKey = Account(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            issuerID: issuerID.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyID: keyID.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKey: key.trimmingCharacters(in: .whitespacesAndNewlines),
            vendorNumber: vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if apiKeysProvider.getApiKey(apiKeyId: apiKey.id) != nil {
            alert = .duplicateKey
            return
        }
        
        if apiKeysProvider.accounts.contains(where: { $0.name == name }) {
            alert = .duplicateName
            return
        }

        Task(priority: .userInitiated) {
            do {
                try await apiKey.checkKey()
                try apiKeysProvider.addApiKey(apiKey: apiKey)
                finishOnboarding()
                let api = AppStoreConnectAPI(apiKey: apiKey)
                _ = try? await api.getData(useCache: true, useMemoization: false)
            } catch let err {
                let apiErr: APIError = (err as? APIError) ?? .unknown
                if apiErr == .invalidCredentials {
                    alert = .invalidKey
                }
            }
        }
    }

    private func finishOnboarding() {
        dismiss()
    }

    private enum OnboardingSection: Identifiable {
        case naming, key

        var id: Self { self }
    }

    // MARK: Alert
    private enum AddAPIKeyAlert: Identifiable {
        case invalidKey
        case duplicateKey
        case duplicateName

        var id: Self { self }
    }

    private func generateAlert(_ alertType: AddAPIKeyAlert) -> Alert {
        let button: Alert.Button
        let title: Text
        let message: Text
        
        switch alertType {
        case .invalidKey:
            title = Text("Invalid Account")
            message = Text("Some or all of the information entered is incorrect.")
            button = Alert.Button.default(Text("OK"))
        case .duplicateKey:
            title = Text("Duplicate Account")
            message = Text("These credencials have already been added.")
            button = Alert.Button.default(Text("Check Again"))
        case .duplicateName:
            title = Text("Duplicate Name")
            message = Text("Choose a unique name.")
            button = Alert.Button.default(Text("OK"))
        }
        return Alert(title: title, message: message, dismissButton: button)
    }

    func infoCard(title: LocalizedStringKey) -> some View {
        DisclosureGroup(content: {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }, label: {
            Label("How to find it", systemImage: "questionmark.circle")
        })
    }

    private struct TextFieldStyle: ViewModifier {
        init(borderColor: Color? = nil, borderWidth: CGFloat = 1, cornerRadius: CGFloat = 5) {
            #if canImport(UIKit)
            self.borderColor = borderColor ?? Color(UIColor.systemGray5)
            #else
            self.borderColor = borderColor ?? Color(NSColor.systemGray)
            #endif
            self.borderWidth = borderWidth
            self.cornerRadius = cornerRadius
        }

        let borderColor: Color
        let borderWidth: CGFloat
        let cornerRadius: CGFloat

        func body(content: Content) -> some View {
            content
                .buttonStyle(.plain)
                .padding(5)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(borderColor, lineWidth: borderWidth))
                .disableAutocorrection(true)
                .font(.system(.body, design: .monospaced))
        }
    }

    enum Fields {
        case name, issuerID, keyID, key, vendor
    }
}

#Preview {
    NewAccountView()
        .preferredColorScheme(.dark)
}
