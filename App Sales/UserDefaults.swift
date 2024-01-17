//
//  UserDefaults.swift
//  App Sales
//
//  Created by Jayden Irwin on 2024-01-16.
//

import Foundation

extension UserDefaults {
    
    struct Key {
        static let whatsNewVersion = "whatsNewVersion"
        @available(*, unavailable)
        static let apiKeys = "apiKeys"
        @available(*, unavailable)
        static let dataCache = "dataCache"
        static let includeRedownloads = "includeRedownloads"
        static let homeSelectedKey = "homeSelectedKey"
        static let lastSeenVersion = "lastSeenVersion"
    }
    
    func register() {
        register(defaults: [
            Key.whatsNewVersion: 0
        ])
    }
    
}
