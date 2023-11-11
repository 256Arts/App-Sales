//
//  ACApp.swift
//  AC Widget by NO-COMMENT
//

import CoreImage
import UIKit

struct ACApp: Codable, Identifiable {
    var id: String { return sku }
    let appleID: String
    let name: String
    let sku: String
    let version: String
    let price: Double
    let currentVersionReleaseDate: String
    let iconURL100: URL
    let iconURL512: URL
    
    var url: URL {
        URL(string: "https://apps.apple.com/app/id" + appleID)!
    }
    var cachedIconURL: URL? {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        
        return groupURL.appending(path: appleID).appendingPathExtension("jpg")
    }
    
    func saveIcon() async {
        guard let cachedIconURL else { return }
        
        let imageData: Data? = await {
            if let data = try? Data(contentsOf: iconURL512) {
                return data
            } else if let data = try? await URLSession.shared.data(from: iconURL512).0 {
                return data
            }
            return nil
        }()
        
        if let imageData {
            FileManager.default.createFile(atPath: cachedIconURL.path(), contents: imageData)
        }
    }

    static func == (lhs: ACApp, rhs: ACApp) -> Bool {
        return lhs.id == rhs.id
    }
    
    static let demo1 = ACApp(
        appleID: "1",
        name: "Forest Explorer",
        sku: "1",
        version: "1.0",
        price: 0.99,
        currentVersionReleaseDate: "",
        iconURL100: Bundle.main.url(forResource: "Demo Icon 1", withExtension: "png")!,
        iconURL512: Bundle.main.url(forResource: "Demo Icon 1", withExtension: "png")!)
    
    static let demo2 = ACApp(
        appleID: "2",
        name: "Ocean Journal",
        sku: "2",
        version: "1.0",
        price: 0.99,
        currentVersionReleaseDate: "",
        iconURL100: Bundle.main.url(forResource: "Demo Icon 2", withExtension: "png")!,
        iconURL512: Bundle.main.url(forResource: "Demo Icon 2", withExtension: "png")!)
    
    static let demo3 = ACApp(
        appleID: "3",
        name: "Mountain Climber",
        sku: "3",
        version: "1.0",
        price: 0.99,
        currentVersionReleaseDate: "",
        iconURL100: Bundle.main.url(forResource: "Demo Icon 3", withExtension: "png")!,
        iconURL512: Bundle.main.url(forResource: "Demo Icon 3", withExtension: "png")!)
    
    static let demo4 = ACApp(
        appleID: "4",
        name: "Sunset Seeker",
        sku: "4",
        version: "1.0",
        price: 0.99,
        currentVersionReleaseDate: "",
        iconURL100: Bundle.main.url(forResource: "Demo Icon 4", withExtension: "png")!,
        iconURL512: Bundle.main.url(forResource: "Demo Icon 4", withExtension: "png")!)
}
