import SwiftUI

struct Event: Codable {
    let appTitle: String
    let appSKU: String
    let units: Int
    let proceeds: Float
    let date: Date
    let countryCode: String
    let device: String
    let appIdentifier: String
    let type: EventType
}

enum EventType: String, CaseIterable, Codable {
    case download
    case redownload
    case iap
    case restoredIap
    case update
    case unknown

    init(_ productTypeIdentifier: String?) {
        switch productTypeIdentifier {
        case "1", "1-B", "F1-B", "1E", "1EP", "1EU", "1F", "1T", "F1":
            self = .download
        case "3", "3F", "F3":
            self = .redownload
        case "FI1", "IA1", "IA1-M", "IA9", "IA9-M", "IAY", "IAY-M":
            self = .iap
        case "IA3":
            self = .restoredIap
        case "7", "7F", "7T", "F7":
            self = .update
        default:
            self = .unknown
        }
    }
}

enum ACDevice: Hashable {
    case desktop
    case iPhone
    case iPad
    case appleWatch
    case appleTV
    case appleVision
    case iPod
    /// A device the report names that App Sales has no case for, under the report's own name.
    case other(String)

    /// Apple documents iPhone, iPad, iPod touch, Desktop, Apple TV, and Apple Vision.
    init(_ deviceString: String?) {
        switch deviceString {
        case "iPhone":
            self = .iPhone
        case "iPad":
            self = .iPad
        case "iPod", "iPod touch":
            self = .iPod
        case "Apple Vision", "Apple Vision Pro":
            self = .appleVision
        case "Desktop":
            self = .desktop
        case "Apple Watch":
            self = .appleWatch
        case "Apple TV":
            self = .appleTV
        case let name?:
            self = .other(name.trimmingCharacters(in: .whitespaces))
        default:
            self = .other("")
        }
    }

    /// Apple's product names, which are the same in every language.
    var name: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .desktop: "Mac"
        case .appleWatch: "Apple Watch"
        case .appleTV: "Apple TV"
        case .appleVision: "Apple Vision Pro"
        case .iPod: "iPod touch"
        case .other(let name): ["", "UNKNOWN"].contains(name) ? String(localized: "Other") : name
        }
    }

    var symbol: String {
        switch self {
        case .iPhone:
            return "iphone"
        case .iPad:
            return "ipad"
        case .desktop:
            return "desktopcomputer"
        case .appleWatch:
            return "watchface.applewatch.case"
        case .appleTV:
            return "appletv"
        case .appleVision:
            return "vision.pro"
        case .iPod:
            return "ipodtouch"
        case .other:
            return "questionmark"
        }
    }
}
