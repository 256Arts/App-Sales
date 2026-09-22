import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

let appGroupID = "group.com.jaydenirwin.appsales"

class ACDataCache {
    private init() {}

    private static var storageUrl: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private struct CacheObjectCollection: Codable {
        let objects: [CacheObject]
    }

    /// How many days of reports are fetched and kept — the home screen and widgets compare the last 30 days with the 30 before.
    static let retainedDays = 60

    private struct CacheObject: Codable {
        let apiKeyId: String
        let data: ACData
        /// Days App Store Connect had no report for, so they aren't re-requested on every fetch. Optional so older cache files still load.
        let emptyDates: [String]?
    }

    public static func getData(apiKey: Account) -> (data: ACData, emptyDates: Set<String>)? {
        guard let object = getCollection()?.objects.first(where: { $0.apiKeyId == apiKey.id }) else { return nil }
        return (object.data, Set(object.emptyDates ?? []))
    }

    public static func saveData(data: ACData, emptyDates: Set<String> = [], apiKey: Account) {
        var cacheObjects: [CacheObject] = getCollection()?.objects ?? []

        // find existing data for apiKey and remove matching data temporarily from array
        var oldObject: CacheObject?
        cacheObjects.removeAll(where: {
            let matching = $0.apiKeyId == apiKey.id
            if matching { oldObject = $0 }
            return matching
        })
        let oldData = oldObject?.data

        // Convert currency from oldData to data.displayCurrency
        var oldEntries: [Event] = []
        if let oldData = oldData {
            oldEntries = oldData.changeCurrency(to: data.displayCurrency).entries
        }

        // merge items
        let newDates = Set(data.entries.map(\.date))
        let oldDataFiltered = oldEntries.filter { !newDates.contains($0.date) }

        var entries: [Event] = data.entries + oldDataFiltered

        // delete entries older than the window AppStoreConnectAPI fetches
        let validDays = Set(Date.now.dayBefore.getLastNDates(retainedDays).map({ $0.acApiFormat() }))

        entries = entries.filter({ entry in
            validDays.contains(entry.date.acApiFormat())
        })

        let entryDays = Set(entries.map { $0.date.acApiFormat() })
        let allEmptyDates = emptyDates.union(oldObject?.emptyDates ?? [])
            .filter { validDays.contains($0) && !entryDays.contains($0) }

        if !entries.isEmpty || !allEmptyDates.isEmpty {
            let newObj = CacheObject(
                apiKeyId: apiKey.id,
                data: ACData(entries: entries, currency: data.displayCurrency, apps: data.apps),
                emptyDates: allEmptyDates.sorted())
            cacheObjects.append(newObj)
        }

        let collection = CacheObjectCollection(objects: cacheObjects)
        saveCollection(collection)
        
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private static func saveCollection(_ collection: CacheObjectCollection) {
        guard let storageUrl = storageUrl?.appendingPathComponent("cache.json") else { return }
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(collection) {
            do {
                try encoded.write(to: storageUrl)
            } catch {
                print("Caching failed", error)
            }
        }
    }

    private static func getCollection() -> CacheObjectCollection? {
        guard let storageUrl = storageUrl?.appendingPathComponent("cache.json") else { return nil }
        if let savedData: Data = try? Data(contentsOf: storageUrl) {
            let decoder = JSONDecoder()
            let loadedData = try? decoder.decode(CacheObjectCollection.self, from: savedData)
            return loadedData
        }

        return nil
    }

    public static func numberOfEntriesCached(apiKey: Account? = nil) -> Int {
        let cacheObjects: [CacheObject] = getCollection()?.objects ?? []
        let data: [Event] = cacheObjects.filter({
            guard let keyId = apiKey?.id else { return true }
            return $0.apiKeyId == keyId
        }).flatMap({ $0.data.entries })
        return data.count
    }

    public static func clearCache(apiKey: Account) {
        var cacheObjects: [CacheObject] = getCollection()?.objects ?? []
        cacheObjects.removeAll(where: { $0.apiKeyId == apiKey.id })
        let collection = CacheObjectCollection(objects: cacheObjects)
        saveCollection(collection)
        AnalyticsCache.clear(account: apiKey)
    }

    public static func clearCache() {
        guard let storageUrl = storageUrl?.appendingPathComponent("cache.json") else { return }
        try? FileManager.default.removeItem(at: storageUrl)
    }
}
