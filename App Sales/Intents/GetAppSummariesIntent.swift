import AppIntents
import Foundation

/// The per-app breakdown, as entities a shortcut can loop over rather than a block of text.
struct GetAppSummariesIntent: AppIntent {

    static var title: LocalizedStringResource = "Get Sales by App"
    static var description = IntentDescription(
        "Lists each app's downloads and proceeds for an App Store Connect account, best-selling first.",
        categoryName: "Sales",
        resultValueName: "Apps")

    @Parameter(title: "Account")
    var account: Account?

    @Parameter(title: "Period", default: .last30Days)
    var period: SalesPeriod

    static var parameterSummary: some ParameterSummary {
        Summary("Get sales by app for \(\.$period)") {
            \.$account
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[AppSalesEntity]> & ProvidesDialog & ShowsSnippetView {
        let data = try await SalesIntentData.data(for: account)
        let apps = data.getAppSummaries(in: period.dateRange)

        return .result(
            value: apps.map(AppSalesEntity.init),
            dialog: dialog(for: apps),
            view: AppSalesSnippet(period: period, apps: apps, currency: data.displayCurrency))
    }

    private func dialog(for apps: [AppPerformanceSummary]) -> IntentDialog {
        guard let best = apps.first, best.downloads > 0 else {
            return IntentDialog("No sales for \(period.title).")
        }

        return IntentDialog("\(apps.count) apps for \(period.title), led by \(best.name) with \(best.downloads.formatted()) downloads.")
    }
}

/// One app's numbers, so a shortcut can pull out a single field instead of parsing a sentence.
struct AppSalesEntity: AppEntity {

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "App" }
    static var defaultQuery = AppSalesQuery()

    /// The app's Apple ID, which is what `AppPerformanceSummary` identifies itself by too.
    let id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Downloads")
    var downloads: Int

    @Property(title: "Proceeds")
    var proceeds: Double

    @Property(title: "Price")
    var price: Double

    @Property(title: "App Store Link")
    var url: URL

    init(_ summary: AppPerformanceSummary) {
        self.id = summary.appleID
        self.name = summary.name
        self.downloads = summary.downloads
        self.proceeds = summary.proceeds
        self.price = summary.price
        self.url = summary.url
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(downloads.formatted()) downloads",
            image: icon)
    }

    /// The App Group's cached artwork, the same copy the widget draws from. Nil until a fetch has
    /// had a chance to save it, in which case Shortcuts falls back to the app's own icon.
    private var icon: DisplayRepresentation.Image? {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID),
              let data = try? Data(contentsOf: groupURL.appending(path: id).appendingPathExtension("jpg")) else { return nil }

        return DisplayRepresentation.Image(data: data)
    }
}

/// Resolves app entities against the account the app is currently showing, so a saved shortcut that
/// references one app still finds it on the next run.
struct AppSalesQuery: EntityQuery {

    func entities(for identifiers: [AppSalesEntity.ID]) async throws -> [AppSalesEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AppSalesEntity] {
        try await SalesIntentData.data(for: nil).getAppSummaries().map(AppSalesEntity.init)
    }
}
