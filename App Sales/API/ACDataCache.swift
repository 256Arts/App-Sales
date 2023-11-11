//
//  ACDataCache.swift
//  AC Widget by NO-COMMENT
//

import Foundation

let appGroupID = "group.com.jaydenirwin.appsales"

class ACDataCache {
    private init() {}

    private static var storageUrl: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private struct CacheObjectCollection: Codable {
        let objects: [CacheObject]
    }

    private struct CacheObject: Codable {
        let apiKeyId: String
        let data: ACData
    }

    public static func getData(apiKey: Account) -> ACData? {
        guard let collection = getCollection() else { return nil }
        return collection.objects.first(where: { $0.apiKeyId == apiKey.id })?.data
    }

    public static func saveData(data: ACData, apiKey: Account) {
        var cacheObjects: [CacheObject] = getCollection()?.objects ?? []

        // find existing data for apiKey and remove matching data temporarily from array
        var oldData: ACData?
        cacheObjects.removeAll(where: {
            let matching = $0.apiKeyId == apiKey.id
            if matching { oldData = $0.data }
            return matching
        })

        // Convert currency from oldData to data.displayCurrency
        var oldEntries: [Event] = []
        if let oldData = oldData {
            oldEntries = oldData.changeCurrency(to: data.displayCurrency).entries
        }

        // merge items
        let oldDataFiltered = oldEntries.filter { oldEntry in
            return !data.entries.contains(where: { $0.date == oldEntry.date })
        }

        var entries: [Event] = data.entries + oldDataFiltered

        // delete entries from all object that are to old
        let latest: Event? = entries.sorted { a, b in
            a.date.compare(b.date) == .orderedDescending
        }.first

        let latestDate = latest?.date ?? Date()
        let validDays = latestDate.getLastNDates(35).map({ $0.acApiFormat() })

        entries = entries.filter({ entry in
            validDays.contains(entry.date.acApiFormat())
        })

        if !entries.isEmpty {
            let newObj = CacheObject(apiKeyId: apiKey.id, data: ACData(entries: entries, currency: data.displayCurrency, apps: data.apps))
            cacheObjects.append(newObj)
        }

        let collection = CacheObjectCollection(objects: cacheObjects)
        saveCollection(collection)
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
    }

    public static func clearCache() {
        guard let storageUrl = storageUrl?.appendingPathComponent("cache.json") else { return }
        try? FileManager.default.removeItem(at: storageUrl)
    }
}
