import SwiftUI

@main
struct AppSalesWatchApp: App {

    init() {
        ScreenshotMode.prepareLaunch()
    }

    @Bindable private var accountManager = AccountManager.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchHomeView()
            }
            .environment(accountManager)
        }
    }
}
