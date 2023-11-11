//
//  ACData.swift
//  AC Widget by NO-COMMENT
//

import Foundation
import SwiftUI

struct ACData: Codable {
    
    let apps: [ACApp]
    let entries: [Event]
    let displayCurrency: Currency

    init(entries: [Event], currency: Currency, apps: [ACApp]) {
        self.entries = entries
        self.displayCurrency = currency
        self.apps = apps
    }
    
    func changeCurrency(to outputCurrency: Currency) -> ACData {
        let newEntries: [Event] = self.entries.map({ entry -> Event in
            let proceeds = CurrencyConverter.shared.convert(Double(entry.proceeds),
                                                            valueCurrency: self.displayCurrency,
                                                            outputCurrency: outputCurrency) ?? 0
            return Event(appTitle: entry.appTitle,
                           appSKU: entry.appSKU,
                           units: entry.units,
                           proceeds: Float(proceeds),
                           date: entry.date,
                           countryCode: entry.countryCode,
                           device: entry.device,
                           appIdentifier: entry.appIdentifier,
                           type: entry.type)
        })

        return ACData(entries: newEntries, currency: outputCurrency, apps: self.apps)
    }
    
    func getEntries(for type: InfoType, startDate: Date, endDate: Date = .now, filteredApps: [ACApp] = []) -> [Event] {
        var entries = entries.getDays(start: startDate, end: endDate)
        if !filteredApps.isEmpty {
            entries = entries.filter { entry in
                filteredApps.contains(where: { $0.appleID == entry.appIdentifier })
            }
        }

        switch type {
        case .proceeds:
            entries = entries.filter({ $0.proceeds > 0 })
        case .downloads:
            if UserDefaults.shared?.bool(forKey: UserDefaultsKey.includeRedownloads) ?? false {
                entries = entries.filter({ $0.type == .download || $0.type == .redownload })
            } else {
                entries = entries.filter({ $0.type == .download })
            }
        case .updates:
            entries = entries.filter({ $0.type == .update })
        case .iap:
            entries = entries.filter({ $0.type == .iap })
        }

        return entries
    }

    func getRawData(for type: InfoType, lastNDays: Int, filteredApps: [ACApp] = []) -> [(Float, Date)] {
        let startDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -lastNDays, to: .now)!
        return getRawData(for: type, startDate: startDate, filteredApps: filteredApps)
    }
    
    func getRawData(for type: InfoType, startDate: Date, endDate: Date = .now, filteredApps: [ACApp] = []) -> [(Float, Date)] {
        let dict = Dictionary(grouping: getEntries(for: type, startDate: startDate, endDate: endDate, filteredApps: filteredApps), by: { $0.date })
        var result: [(Float, Date)]

        switch type {
        case .proceeds:
            result = dict.map { (key: Date, value: [Event]) -> (Float, Date) in
                return (value.reduce(0, { $0 + $1.proceeds * Float($1.units) }), key)
            }
        default:
            result = dict.map { (key: Date, value: [Event]) -> (Float, Date) in
                return (Float(value.reduce(0, { $0 + $1.units })), key)
            }
        }

        return result
    }

    // MARK: Get Device
    func getDevices(_ type: InfoType, lastNDays: Int, filteredApps: [ACApp] = []) -> [(String, Float)] {
        let startDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -lastNDays, to: .now)!
        let dict = Dictionary(grouping: getEntries(for: type, startDate: startDate, filteredApps: filteredApps), by: { $0.device })
        var result: [(String, Float)]

        switch type {
        case .proceeds:
            result = dict.map { (key: String, value: [Event]) -> (String, Float) in
                return (key, value.reduce(0, { $0 + $1.proceeds * Float($1.units) }))
            }
        default:
            result = dict.map { (key: String, value: [Event]) -> (String, Float) in
                return (key, Float(value.reduce(0, { $0 + $1.units })))
            }
        }

        return result
    }

    // MARK: Get Change
    func getChange(_ type: InfoType) -> Float {
        let latestInterval = getRawData(for: type, lastNDays: 15).map({ $0.0 }).reduce(0, +)
        let previousInterval = getRawData(for: type, lastNDays: 30).map({ $0.0 }).reduce(0, +) - latestInterval
        return ((latestInterval/previousInterval) - 1) * 100
    }
    
    func getChange(_ type: InfoType) -> String {
        let change = NSNumber(value: getChange(type))
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 1
        return nf.string(from: change) ?? "-"
    }
    
    func getPerformanceSummary() -> PerformanceSummary {
        let thirtyDaysAgo = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -30, to: .now)!
        let sixtyDaysAgo = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -60, to: .now)!
        
        let downloads = Int(getRawData(for: .downloads, startDate: thirtyDaysAgo).reduce(0, { $0 + $1.0 }))
        let prevDownloads = Int(getRawData(for: .downloads, startDate: sixtyDaysAgo, endDate: thirtyDaysAgo).reduce(0, { $0 + $1.0 }))
        let proceeds = Double(getRawData(for: .proceeds, startDate: thirtyDaysAgo).reduce(0, { $0 + $1.0 }))
        let prevProceeds = Double(getRawData(for: .proceeds, startDate: sixtyDaysAgo, endDate: thirtyDaysAgo).reduce(0, { $0 + $1.0 }))
        
        return PerformanceSummary(
            downloads: downloads,
            prevDownloads: prevDownloads,
            proceeds: proceeds,
            prevProceeds: prevProceeds,
            apps: Array(getAppSummaries().prefix(6)))
    }
    
    // MARK: Get by app
    func getAppSummaries() -> [AppPerformanceSummary] {
        let appsAndDownloads: [(ACApp, Int)] = apps.map({
            ($0, getRawData(for: .downloads, lastNDays: 30, filteredApps: [$0]).reduce(0, { $0 + Int($1.0) }))
        })
        return appsAndDownloads.sorted(by: { $0.1 > $1.1 }).map({
            let proceeds = Double(getRawData(for: .proceeds, lastNDays: 30, filteredApps: [$0.0]).reduce(0.0, { $0 + $1.0 }))
            return AppPerformanceSummary(appleID: $0.0.appleID, name: $0.0.name, iconURL: $0.0.iconURL100, downloads: $0.1, proceeds: proceeds)
        })
    }

    // MARK: Getting Dates
    func latestReportingDate() -> Date {
        return entries.map({ $0.date }).reduce(Date.distantPast, { $0 > $1 ? $0 : $1 })
    }
    
    static let example = createMockData(60)

    private static func createMockData(_ days: Int) -> ACData {
        var entries: [Event] = []
        let apps: [ACApp] = [.demo1, .demo2, .demo3, .demo4]
        let countries = ["US", "DE", "ES", "UK", "IN", "CA", "SE", "NZ"]
        let devices = ["Desktop", "iPhone", "iPad"]

        for day in -days...0 {
            let app = apps.randomElement()!
            let multiplier = (5 - (Float(app.id) ?? 1)) * (day < -days/2 ? 0.88 : 1)
            entries.append(Event(
                appTitle: app.name,
                appSKU: app.sku,
                units: Int(multiplier * Float.random(in: 1...20)),
                proceeds: multiplier * Float.random(in: 0...0.2),
                date: Calendar.current.date(byAdding: .day, value: day, to: .now)!,
                countryCode: countries.randomElement()!,
                device: devices.randomElement()!,
                appIdentifier: app.appleID,
                type: .download))
        }
        
        for app in apps {
            Task {
                await app.saveIcon()
            }
        }
        
        return ACData(entries: entries, currency: .USD, apps: apps)
    }
}

enum InfoType {
    case proceeds, downloads, updates, iap

    var systemImage: String {
        switch self {
        case .proceeds:
            return "dollarsign.circle"
        case .downloads:
            return "square.and.arrow.down"
        case .updates:
            return "arrow.triangle.2.circlepath"
        case .iap:
            return "cart"
        }
    }
}
