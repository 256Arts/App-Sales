import SwiftUI
import StoreKit

@main
struct AppSalesApp: App {
    
    init() {
        ScreenshotMode.prepareLaunch()
        WidgetShots.renderIfRequested()
    }
    
    @AppStorage(UserDefaults.Key.appLaunchCount) var appLaunchCount = 0
    
    @Environment(\.requestReview) private var requestReview
    
    @Bindable private var apiKeysProvider = AccountManager.shared
    
    @State private var showingEvent = false

    @Environment(\.scenePhase) private var scenePhase

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
            // The AI usage figures move while the work is being done, so while the app is up they
            // are read once a minute and handed to the widget, which cannot ask that often itself.
            .task(id: scenePhase) {
                guard scenePhase == .active, !ScreenshotMode.isActive else { return }

                while !Task.isCancelled {
                    await AIAssistants.shared.refreshConnected()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
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
        // itself is one nobody asked for. A screenshot run always shows it, since it is one of the shots.
        MenuBarExtra(isInserted: ScreenshotMode.isActive ? .constant(true) : $showsMenuBarExtra) {
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
