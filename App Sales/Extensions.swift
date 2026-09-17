import Foundation
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif
import KeychainAccess

extension Date {
    var dayBefore: Date {
        return Calendar.current.date(byAdding: .day, value: -1, to: self) ?? self
    }

    func getCETHour() -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(abbreviation: "CET") ?? .current
        return calendar.component(.hour, from: self)
    }
}

// MARK: User Defaults
extension UserDefaults {
    static var shared: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
}

// MARK: Formatting
extension NumberFormatter {
    /// Proceeds and prices, in the reader's own locale.
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter
    }()
}

// MARK: Editing Strings
extension String {
    func removeCharacters(from set: CharacterSet) -> String {
        var newString = self
        newString.removeAll { char -> Bool in
            guard let scalar = char.unicodeScalars.first else { return false }
            return set.contains(scalar)
        }
        return newString
    }

    func countryCodeToName() -> String {
        return (Locale.current as NSLocale).localizedString(forCountryCode: self) ?? ""
    }
}

// MARK: ACEntry Array
extension Array where Element == Event {
    func getDays(start: Date, end: Date = .now) -> [Event] {
        self.filter({ start <= $0.date && $0.date < end })
    }
}

// MARK: Other
extension Collection {
    func count(where test: (Element) throws -> Bool) rethrows -> Int {
        return try self.filter(test).count
    }
}
