import Foundation
import SwiftUI

struct PerformanceSummary {
    let downloads: Int
    let prevDownloads: Int
    let proceeds: Double
    let prevProceeds: Double
    /// Every app, best-selling first. Views that only have room for a few take `topApps`.
    let apps: [AppPerformanceSummary]

    /// The handful of apps the chart and the widget graphics have room for.
    var topApps: [AppPerformanceSummary] {
        Array(apps.prefix(6))
    }
    
    var downloadsPercentageChange: Double {
        PerformanceSummary.percentageChange(from: Double(prevDownloads), to: Double(downloads))
    }
    var proceedsPercentageChange: Double {
        PerformanceSummary.percentageChange(from: prevProceeds, to: proceeds)
    }

    /// Fractional change between two windows, capped at +999% so a first sale out of nothing cannot
    /// print an arrow the width of the row. Shared with the intents, which report metrics this
    /// summary does not carry.
    static func percentageChange(from previous: Double, to current: Double) -> Double {
        guard previous > 0 else { return current == 0 ? 0 : 9.99 }

        return min(current / previous - 1, 9.99)
    }
}

struct AppPerformanceSummary: Identifiable {
    let appleID: String
    var id: String { appleID }
    let name: String
    let iconURL: URL
    let downloads: Int
    let proceeds: Double
    let price: Double

    var url: URL {
        URL(string: "https://apps.apple.com/app/id" + appleID) ?? URL(filePath: "/")
    }
    var cachedIconURL: URL? {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        
        return groupURL.appending(path: appleID).appendingPathExtension("jpg")
    }
    
    var cachedIcon: Image? {
        guard let path = cachedIconURL?.path(percentEncoded: false), let data = FileManager.default.contents(atPath: path) else { return nil }
        
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #else
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #endif
    }
}

/// The orders the home screen's app list can be sorted into.
enum AppListSort: String, CaseIterable, Identifiable {
    case downloads
    case proceeds
    case price
    case websiteViews
    case appStoreViews
    case name

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .downloads: "Downloads"
        case .proceeds: "Proceeds"
        case .price: "Price"
        case .websiteViews: "Website Views"
        case .appStoreViews: "App Store Views"
        case .name: "Name"
        }
    }

    var systemImage: String {
        switch self {
        case .downloads: "arrow.down.app"
        case .proceeds: "dollarsign.circle"
        case .price: "tag"
        case .websiteViews: "globe"
        case .appStoreViews: "doc.text.magnifyingglass"
        case .name: "textformat"
        }
    }

    /// Highest first for the numbers, A–Z for the name. The view counts are keyed by Apple ID, and
    /// apps tied on views — every app, while the views have not loaded — fall back to downloads.
    func sort(_ apps: [AppPerformanceSummary], websiteViews: [String: Int] = [:], appStoreViews: [String: Int] = [:]) -> [AppPerformanceSummary] {
        func byViews(_ views: [String: Int]) -> [AppPerformanceSummary] {
            apps.sorted { a, b in
                let (aViews, bViews) = (views[a.appleID] ?? 0, views[b.appleID] ?? 0)
                return aViews == bViews ? a.downloads > b.downloads : aViews > bViews
            }
        }

        return switch self {
        case .downloads: apps.sorted(by: { $0.downloads > $1.downloads })
        case .proceeds: apps.sorted(by: { $0.proceeds > $1.proceeds })
        case .price: apps.sorted(by: { $0.price > $1.price })
        case .websiteViews: byViews(websiteViews)
        case .appStoreViews: byViews(appStoreViews)
        case .name: apps.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }
}
