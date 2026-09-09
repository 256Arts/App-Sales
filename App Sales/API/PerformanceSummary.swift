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
        guard prevDownloads > 0 else { return downloads == 0 ? 0 : 9.99 }
        
        return min(Double(downloads) / Double(prevDownloads) - 1, 9.99)
    }
    var proceedsPercentageChange: Double {
        guard prevProceeds > 0 else { return proceeds == 0 ? 0 : 9.99 }
        
        return min((proceeds / prevProceeds) - 1, 9.99)
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
        guard let path = cachedIconURL?.path(), let data = FileManager.default.contents(atPath: path) else { return nil }
        
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
    case name

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .downloads: "Downloads"
        case .proceeds: "Proceeds"
        case .price: "Price"
        case .name: "Name"
        }
    }

    var systemImage: String {
        switch self {
        case .downloads: "arrow.down.app"
        case .proceeds: "dollarsign.circle"
        case .price: "tag"
        case .name: "textformat"
        }
    }

    /// Highest first for the numbers, A–Z for the name.
    func sort(_ apps: [AppPerformanceSummary]) -> [AppPerformanceSummary] {
        switch self {
        case .downloads: apps.sorted(by: { $0.downloads > $1.downloads })
        case .proceeds: apps.sorted(by: { $0.proceeds > $1.proceeds })
        case .price: apps.sorted(by: { $0.price > $1.price })
        case .name: apps.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }
}
