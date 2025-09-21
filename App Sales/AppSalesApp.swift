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
        .defaultSize(CGSize(width: 500, height: 700))
        .commands {
            CommandGroup(after: .help) {
                AppSalesApp.links()
            }
        }
    }
    
    @ViewBuilder
    static func links() -> some View {
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
