//
//  PerformanceSummary.swift
//  App Sales
//
//  Created by 256 Arts Developer on 2023-10-26.
//

import Foundation
import SwiftUI

struct PerformanceSummary {
    let downloads: Int
    let prevDownloads: Int
    let proceeds: Double
    let prevProceeds: Double
    let apps: [AppPerformanceSummary]
    
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
