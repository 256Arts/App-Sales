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
