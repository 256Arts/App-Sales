import AppIntents

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
    }
}
