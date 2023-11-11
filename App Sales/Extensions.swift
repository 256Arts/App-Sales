//
//  Extensions.swift
//  AC Widget by NO-COMMENT
//

import Foundation
import SwiftUI
import WidgetKit
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

    func getPSTHour() -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(abbreviation: "PST") ?? .current
        return calendar.component(.hour, from: self)
    }

    func getJSTHour() -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "JST") ?? .current
        return calendar.component(.hour, from: self)
    }

    func getMinutes() -> Int {
        return Calendar(identifier: .gregorian).component(.minute, from: self)
    }

    func nextFullHour() -> Date {
        if let next = Calendar.current.date(bySetting: .minute, value: 0, of: self) {
            return next.addingTimeInterval(60 * 60) // next hour
        }

        return self
    }

    func nextDateWithMinute(_ minute: Int) -> Date {
        if let next = Calendar.current.date(bySetting: .minute, value: 30, of: self) {
            return next
        }

        return self
    }

    func dateToMonthNumber() -> Int {
        return Int(Calendar.current.component(.day, from: self))
    }

    static var appInstallDate: Date {
        if let documentsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last {
            if let installDate = try? FileManager.default.attributesOfItem(atPath: documentsFolder.path)[.creationDate] as? Date {
                return installDate
            }
        }
        return .now // Should never execute
    }
}

extension Calendar {
    func numberOfDaysBetween(_ from: Date, and to: Date) -> Int {
        let fromDate = startOfDay(for: from)
        let toDate = startOfDay(for: to)
        let numberOfDays = dateComponents([.day], from: fromDate, to: toDate)

        return numberOfDays.day ?? 0
    }
}

// MARK: User Defaults
extension UserDefaults {
    static var shared: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
}

enum UserDefaultsKey {
    @available(*, unavailable)
    static let apiKeys = "apiKeys"
    @available(*, unavailable)
    static let dataCache = "dataCache"
    static let includeRedownloads = "includeRedownloads"
    static let homeSelectedKey = "homeSelectedKey"
    static let lastSeenVersion = "lastSeenVersion"
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
