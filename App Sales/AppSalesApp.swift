//
//  AppSalesApp.swift
//  AC Widget by NO-COMMENT
//

import SwiftUI
import WidgetKit

@main
struct AppSalesApp: App {
    
    @StateObject private var apiKeysProvider = AccountProvider.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .environmentObject(apiKeysProvider)
            .onAppear {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
