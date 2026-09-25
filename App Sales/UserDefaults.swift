import Foundation

extension UserDefaults {
    
    struct Key {
        static let appLaunchCount = "appLaunchCount"
        static let includeRedownloads = "includeRedownloads"
        static let homeSelectedKey = "homeSelectedKey"
        static let appListSort = "appListSort"
        static let homeChartSort = "homeChartSort"
        static let homeChartShowsActiveDevices = "homeChartShowsActiveDevices"
        /// How the AI usage figures read. In the App Group, because the widgets and the Mac's menu
        /// bar extra draw the same figures and have to agree with the app about which way round.
        static let aiUsageMetric = "aiUsageMetric"
        static let aiUsageTimeStyle = "aiUsageTimeStyle"
        static let aiUsageGoal = "aiUsageGoal"
        static let aiUsageHidesUnreachable = "aiUsageHidesUnreachable"
        static let aiUsageMenuBarExtra = "aiUsageMenuBarExtra"
        static let aiUsageMenuBarStyle = "aiUsageMenuBarStyle"
        /// What the AI usage widget has learned about how often each assistant's figures move.
        static let aiUsageWidgetPacing = "aiUsageWidgetPacing"
    }
    
    func register() {
        register(defaults: [
            Key.appLaunchCount: 0
        ])
    }
    
}
