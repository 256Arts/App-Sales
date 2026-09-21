import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// One account's sales data, and the fetch that produces it.
///
/// Every platform's home screen wants the same three states — loading, loaded, failed — and the
/// same refresh behaviour, so they share one loader rather than each keeping its own pair of
/// `@State`s and its own copy of the error handling.
@MainActor
@Observable
final class SalesDataLoader {

    private(set) var data: ACData?
    /// Kept alongside the data rather than computed on demand: rolling 60 days of events up is real
    /// work, and a view body reads it more than once per pass.
    private(set) var summary: PerformanceSummary?
    private(set) var error: APIError?

    init(data: ACData? = nil) {
        self.data = data
        self.summary = data?.getPerformanceSummary()
    }

    /// The reader's own currency, which is what the home screens display in.
    private var displayCurrency: Currency? {
        Currency(rawValue: Locale.autoupdatingCurrent.currency?.identifier ?? "")
    }

    /// - Parameter useMemoization: `false` for a refresh the reader asked for, which should go past
    ///   the five-minute in-memory cache; `true` for a view simply appearing.
    func load(account: Account?, useMemoization: Bool = true) async {
        guard let account else { return }

        let api = AppStoreConnectAPI(apiKey: account)
        do {
            let data = try await api.getData(currency: displayCurrency, useMemoization: useMemoization)
            self.data = data
            self.summary = data.getPerformanceSummary()
            error = nil
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch is CancellationError {
        } catch let err as URLError where err.code == .cancelled {
        } catch let err {
            data = nil
            summary = nil
            error = APIError(err)
        }
    }
}
