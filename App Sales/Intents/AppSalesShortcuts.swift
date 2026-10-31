import AppIntents
import AIUsageKitIntents
import AppSalesKit

/// The shortcuts that exist the moment the app is installed — no setup in the Shortcuts app first.
///
/// Every phrase carries `\(.applicationName)`, which Siri requires, and each intent's parameters
/// have defaults so an unqualified "how much did my apps make" still answers.
struct AppSalesShortcuts: AppShortcutsProvider {

    static var shortcutTileColor: ShortcutTileColor { .lime }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetPerformanceSummaryIntent(),
            phrases: [
                "Get my \(.applicationName) summary",
                "How much did my apps make in \(.applicationName)",
                "How are my apps doing in \(.applicationName)",
                "Check my sales in \(.applicationName)",
            ],
            shortTitle: "Sales Summary",
            systemImageName: "chart.line.uptrend.xyaxis")

        AppShortcut(
            intent: GetAppSummariesIntent(),
            phrases: [
                "Get my \(.applicationName) sales by app",
                "Which of my apps sold best in \(.applicationName)",
                "Show my app breakdown in \(.applicationName)",
            ],
            shortTitle: "Sales by App",
            systemImageName: "square.grid.2x2")

        AppShortcut(
            intent: GetAIUsageIntent(),
            phrases: [
                "Get my \(.applicationName) AI usage",
                "How much Claude have I got left in \(.applicationName)",
                "How much AI usage is left in \(.applicationName)",
                "Check my AI limits in \(.applicationName)",
            ],
            shortTitle: "AI Usage",
            systemImageName: "gauge.with.dots.needle.33percent")
    }
}

/// Brings AppSalesKit's account and metric, and AIUsageKit's intent, its assistant picker, and its
/// widget configuration into the app's App Intents metadata.
struct AppSalesIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [AppSalesKitPackage.self, AIUsageKitIntentsPackage.self]
    }
}
