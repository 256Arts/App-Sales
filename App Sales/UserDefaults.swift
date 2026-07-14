import Foundation

extension UserDefaults {
    
    struct Key {
        static let appLaunchCount = "appLaunchCount"
        static let includeRedownloads = "includeRedownloads"
        static let homeSelectedKey = "homeSelectedKey"
    }
    
    func register() {
        register(defaults: [
            Key.appLaunchCount: 0
        ])
    }
    
}
