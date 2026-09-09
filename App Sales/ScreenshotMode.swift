import Foundation

/// Deterministic demo state for App Store screenshots, switched on by the `-screenshotMode` launch
/// argument the UI test passes.
///
/// The app is a window onto whatever App Store Connect account is in the Keychain, so a shot taken
/// on a real machine would either be the "No Account" empty state or the developer's own sales.
/// A screenshot run instead gets demo accounts handed to it in memory — the whole fetch pipeline
/// already short-circuits to `ACData.example` for those (see `Account.isDemo`) — and never reads or
/// writes the real, iCloud-synchronized Keychain.
///
/// Nothing here pins a date: `ACData.example` builds its entries as day offsets from `.now`, so the
/// numbers are the same whichever month a run happens in.
enum ScreenshotMode {

    /// Whether this launch is a screenshot run. Read by `AppSalesApp.init`, by `AccountManager` to
    /// stay off the Keychain, and by `InsightsView` to show a fixed insight.
    static let isActive = ProcessInfo.processInfo.arguments.contains("-screenshotMode")

    /// The accounts the app runs against during a screenshot run.
    ///
    /// More than one, because the Accounts screen is one of the shots and a single row reads as an
    /// app nobody uses. They all share the demo issuer ID, so every one of them serves
    /// `ACData.example` instead of reaching the network.
    static let accounts: [Account] = [
        Account.demoAccount(named: "256 Arts", id: "demo"),
        Account.demoAccount(named: "Indie Side Projects", id: "demo-indie"),
        Account.demoAccount(named: "Client Work", id: "demo-client"),
    ]

    /// The Insights text to photograph, in place of the on-device model's.
    ///
    /// Foundation Models is unavailable in the simulator, so on iPhone, iPad, and Vision the section
    /// would not render at all; on the Mac it renders, but writes something different every run.
    /// Neither makes a screenshot. Deliberately free of numbers, so it cannot go stale against the
    /// seeded data.
    static let insight = """
        Downloads and proceeds are both up on the previous 30 days, and by a similar amount — the \
        extra installs are converting as well as the ones before them, rather than a one-off spike \
        flattering the totals.

        Forest Explorer is carrying the quarter: it out-earns every other title and is still \
        growing. Sunset Seeker is the soft spot, trailing on both downloads and revenue, and is the \
        obvious place to spend your next update.
        """

    /// Puts the preferences a shot can see back to their defaults.
    ///
    /// The app list's sort order is remembered between launches, so a simulator that has been driven
    /// by hand would otherwise photograph whichever order was left behind.
    static func resetPreferences() {
        UserDefaults.shared?.removeObject(forKey: UserDefaults.Key.appListSort)
    }

    #if os(macOS)
    /// Forgets the window size AppKit would otherwise restore.
    ///
    /// The shot is meant to show the app's own `defaultSize`, but a saved frame wins over it. The
    /// runner clears those defaults itself — except it shells out to `defaults`, which resolves a
    /// sandboxed app's domain to its container and so deletes nothing for this app. Doing it from
    /// inside the sandbox is the only thing that reaches them, and this costs only the remembered
    /// window position.
    static func clearSavedWindowLayout() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSWindow Frame") {
            defaults.removeObject(forKey: key)
        }
    }
    #endif
}
