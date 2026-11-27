import AppIntents
import CoreSpotlight
import Observation
import AppSalesKit

/// Opens one app's screen — what a Spotlight hit on an app runs, and a Shortcuts action of its own.
struct OpenAppIntent: OpenIntent {

    static let title: LocalizedStringResource = "Open App Details"
    static let description = IntentDescription(
        "Opens an app's sales, ratings, and reviews in App Sales.",
        categoryName: "Sales")

    @Parameter(title: "App")
    var target: AppSalesEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigation.shared.requestedAppleID = target.id
        return .result()
    }
}

/// An app an intent asked the home screen to show, held until a home screen takes it — which may be
/// after a cold launch, or once the Mac's window is back.
@MainActor
@Observable
final class AppNavigation {
    static let shared = AppNavigation()

    var requestedAppleID: String?
    /// A screen an App Store in-app event link asked the home screen to show; see `appStoreEvent(from:)` and `AppSalesApp`'s `onOpenURL`.
    var requestedEventDestination: AppStoreEventDestination?
}

/// A screen the App Store in-app event link can route to. Raw values are the allowlisted `destination` query values.
enum AppStoreEventDestination: String, CaseIterable, Sendable {
    case summary, accounts, websites
}

/// The parsed `title`/`destination` query items from an App Store in-app event link, if any.
struct AppStoreEventLink: Equatable {
    var title: String?
    var destination: AppStoreEventDestination?
}

extension AppNavigation {

    /// Parses `https://www.256arts.com/appsales/appstoreevent`, optionally with `title` and `destination` query items.
    /// Returns `nil` for any other host/path. Unknown `destination` values and duplicate params are handled safely
    /// (first occurrence of each param wins; an unrecognized destination parses to `nil`, not an error).
    nonisolated static func appStoreEvent(from url: URL) -> AppStoreEventLink? {
        guard url.scheme == "https", url.host() == "www.256arts.com", url.path() == "/appsales/appstoreevent" else { return nil }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let title = items.first { $0.name == "title" }?.value.flatMap { $0.isEmpty ? nil : $0 }
        let destination = items.first { $0.name == "destination" }?.value.flatMap(AppStoreEventDestination.init(rawValue:))
        return AppStoreEventLink(title: title, destination: destination)
    }

}

/// Keeps Spotlight's apps in step with the account on screen.
///
/// `AppSalesQuery` resolves apps against the current account only, so another account's apps would
/// be hits that open nothing: they are cleared on the first index of a launch and whenever the account
/// changes. The demo account's made-up apps are only ever indexed for a screenshot run.
@MainActor
enum AppSpotlightIndex {

    /// The account whose apps are in the index, as far as this launch knows.
    private static var indexedAccountID: String?

    /// Called after each successful load of `account`'s sales.
    static func update(apps: [AppPerformanceSummary], account: Account) async {
        guard !account.isDemo || ScreenshotMode.isActive else {
            await clear()
            return
        }

        let index = CSSearchableIndex.default()
        if indexedAccountID != account.id {
            indexedAccountID = account.id
            try? await index.deleteAppEntities(ofType: AppSalesEntity.self)
        }
        try? await index.indexAppEntities(apps.map(AppSalesEntity.init))
    }

    static func clear() async {
        indexedAccountID = nil
        try? await CSSearchableIndex.default().deleteAppEntities(ofType: AppSalesEntity.self)
    }
}
