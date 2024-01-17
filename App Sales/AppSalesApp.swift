//
//  AppSalesApp.swift
//  AC Widget by NO-COMMENT
//

import SwiftUI

let appWhatsNewVersion = 1

@main
struct AppSalesApp: App {
    
    init() {
        UserDefaults.standard.register()
    }
    
    @StateObject private var apiKeysProvider = AccountManager.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .environmentObject(apiKeysProvider)
        }
        .defaultSize(CGSize(width: 600, height: 800))
        
        #if os(macOS)
        Settings {
            SettingsView()
                .scenePadding()
                .environmentObject(accountManager)
        }
        .defaultSize(width: 400, height: 400)
        #endif
    }
}
