//
//  AppSalesApp.swift
//  AC Widget by NO-COMMENT
//

import SwiftUI
import StoreKit

@main
struct AppSalesApp: App {
    
    init() {
        UserDefaults.standard.register()
    }
    
    @AppStorage(UserDefaults.Key.appLaunchCount) var appLaunchCount = 0
    
    @Environment(\.requestReview) private var requestReview
    
    @Bindable private var apiKeysProvider = AccountManager.shared
    
    @State private var showingEvent = false

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .environment(apiKeysProvider)
            .onAppear {
                appLaunchCount += 1
                if [5, 20, 50, 100].contains(appLaunchCount) {
                    requestReview()
                }
            }
            .alert("Event Intro", isPresented: $showingEvent) {
                Button("OK") { }
            } message: {
                Text("Now let's celebrate by connecting your App Store Connect account and trying out the new features!")
            }
            .onOpenURL { url in
                if url.path().contains("appsales/appstoreevent") {
                    showingEvent = true
                }
            }
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
