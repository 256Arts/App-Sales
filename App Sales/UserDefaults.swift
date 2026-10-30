import Foundation

extension UserDefaults {
    
    struct Key {
        static let appLaunchCount = "appLaunchCount"
        static let includeRedownloads = "includeRedownloads"
        static let homeSelectedKey = "homeSelectedKey"
        static let appListSort = "appListSort"
        static let appListHiddenStats = "appListHiddenStats"
        static let homeChartSort = "homeChartSort"
        static let homeChartShowsActiveDevices = "homeChartShowsActiveDevices"
    }
    
    func register() {
        register(defaults: [
            Key.appLaunchCount: 0
        ])
    }
    
}
