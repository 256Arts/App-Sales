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
        #if os(macOS)
        // One window: it already holds every account and app, so a second would only repeat it, and
        // opening it again (the Dock, the menu bar extra) brings this one forward instead.
        Window("App Sales", id: Self.mainWindowID) {
            mainWindow
        }
        .defaultSize(CGSize(width: 1000, height: 700))
        .commands {
            AppSalesCommands()
        }

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
        #else
        WindowGroup(id: Self.mainWindowID) {
            mainWindow
        }
        .defaultSize(CGSize(width: 1000, height: 700))
        .commands {
            AppSalesCommands()
        }
        #endif
    }

    private var mainWindow: some View {
        HomeView()
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

/// The menu bar: accounts where Settings would be, refreshing and the app list's options in View,
/// and the 256 Arts links in place of a help book the app does not have.
private struct AppSalesCommands: Commands {

    @FocusedValue(\.homeCommands) private var home

    @AppStorage(UserDefaults.Key.homeSelectedKey, store: UserDefaults.shared) private var keyID = ""

    private var accountManager: AccountManager { .shared }

    /// The account the home screen shows, which is the first one until the reader picks another.
    private var currentAccount: Binding<String> {
        Binding {
            accountManager.getApiKey(apiKeyId: keyID)?.id ?? accountManager.accounts.first?.id ?? ""
        } set: {
            keyID = $0
        }
    }

    var body: some Commands {
        // Accounts are all App Sales has to set up, so they take the Settings item and its shortcut.
        CommandGroup(replacing: .appSettings) {
            Button("Accounts…") { home?.showAccounts() }
                .keyboardShortcut(",")
                .disabled(home == nil)
        }

        CommandGroup(before: .toolbar) {
            Button("Refresh") { home?.refresh() }
                .keyboardShortcut("r")
                .disabled(home == nil)

            Divider()

            if accountManager.accounts.count > 1 {
                Picker("Account", selection: currentAccount) {
                    ForEach(accountManager.accounts) { account in
                        Text(account.name)
                            .tag(account.id)
                    }
                }
            }

            if let countedStats = home?.countedStats {
                AppListOptions(countedStats: countedStats, inMenuBar: true)
            }

            Divider()
        }

        CommandGroup(replacing: .help) {
            AppSalesApp.links()
        }
    }
}
