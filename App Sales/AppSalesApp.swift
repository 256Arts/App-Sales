import SwiftUI
import StoreKit

@main
struct AppSalesApp: App {
    
    init() {
        ScreenshotMode.prepareLaunch()
    }
    
    @AppStorage(UserDefaults.Key.appLaunchCount) var appLaunchCount = 0
    
    @Environment(\.requestReview) private var requestReview
    
    @Bindable private var apiKeysProvider = AccountManager.shared
    
    @State private var showingEvent = false

    #if os(macOS)
    @AppStorage(UserDefaults.Key.aiUsageMenuBarExtra, store: UserDefaults.shared) private var showsMenuBarExtra = false
    #endif

    static let mainWindowID = "main"

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
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
            .screenshotModeStatus()
            #if os(macOS)
            .onAppear { DockIcon.windowOpened() }
            .onDisappear { DockIcon.windowClosed() }
            #endif
        }
        .defaultSize(CGSize(width: 500, height: 700))
        .commands {
            CommandGroup(after: .help) {
                AppSalesApp.links()
            }
        }

        #if os(macOS)
        // Off until the reader turns it on in the AI Usage options — a menu bar item that installs
        // itself is one nobody asked for.
        MenuBarExtra(isInserted: $showsMenuBarExtra) {
            AIUsageMenuBar()
        } label: {
            AIUsageMenuBarLabel()
        }
        .menuBarExtraStyle(.window)
        .onChange(of: showsMenuBarExtra, initial: true) {
            DockIcon.menuBarExtra(isShown: showsMenuBarExtra)
        }
        #endif
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
