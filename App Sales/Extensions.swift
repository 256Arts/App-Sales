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
}

extension Text {
    /// When the figures above were last read, as "Updated 8 minutes ago".
    ///
    /// Drawn from `.currentDate`, so it counts up on its own — in a widget between timeline entries
    /// as well as in the app — with nothing holding a clock for it. Minutes are as fine as it goes: a
    /// line that ticks every second pulls the eye for no reason.
    init(updated date: Date) {
        self.init("Updated \(Text(.currentDate, format: .reference(to: date, allowedFields: [.day, .hour, .minute], maxFieldCount: 1)))")
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
