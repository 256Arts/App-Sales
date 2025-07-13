//
//  AppSalesApp.swift
//  AC Widget by NO-COMMENT
//

import SwiftUI

@main
struct AppSalesApp: App {
    
    init() {
        UserDefaults.standard.register()
    }
    
    @Bindable private var apiKeysProvider = AccountManager.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .environment(apiKeysProvider)
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
