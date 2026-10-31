# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

App Sales is a multiplatform SwiftUI app (iOS, macOS, visionOS) that displays App Store Connect sales/proceeds data, plus a standalone watchOS app and two WidgetKit extensions showing the same summaries. It's a fork of "AC Widget by NO-COMMENT" (MIT; attribution lives in `LICENSE`), now maintained by 256 Arts.

## Build & Test

There is no Swift Package manifest, Makefile, or CI — this is an Xcode project driven by `App Sales.xcodeproj`.

```bash
# Build the app (choose a -destination appropriate for your goal)
xcodebuild -project "App Sales.xcodeproj" -scheme "App Sales" build

# Build the widget extension
xcodebuild -project "App Sales.xcodeproj" -scheme "WidgetsExtension" build
```

There are **no unit tests** — don't invent them. The only tests are the UI screenshot walk (`App Sales UITests`, `App Sales Watch UITests`), run via `Scripts/screenshots.sh`. Verify other changes by building and running. SwiftLint is configured (`.swiftlint.yml`) and runs as a build phase if installed; note `force_unwrapping` is an **error**, not a warning. Swift files have no header comments.

Schemes: `App Sales` (main app), `WidgetsExtension` (widget), `App Sales Watch App` (watch app + its complications), `Screenshots` / `Screenshots Watch` (the App Store screenshot runs). Platforms: iOS, macOS, visionOS, watchOS.

The watch app and `Watch Widgets` are separate targets because watchOS is not one of the destinations a multiplatform app target can carry. They share the `App Sales` source folder through synchronized-group membership exceptions, so **a new file under `App Sales/Views/` or `App Sales/Intents/` is compiled into the watch targets unless you add it to their exception lists** in `project.pbxproj` (search for `folder in "App Sales Watch App" target`).

## Architecture

- **[AppSalesKit](https://github.com/256Arts/AppSalesKit)** (`Repos/AppSalesKit`; its AGENTS.md has the model details) — the data model, networking, and every view but the shell: `Account`/`AccountManager`, `AppStoreConnectAPI`, `ACData`, the caches, `AnalyticsReportsAPI`, `CustomerReviewsAPI`, `GoogleAnalytics`, `AdMob`, `SalesDataLoader`, `ScreenshotMode`, `UserDefaults.Key`, and the views (`SalesSummarySection`, `SharePiesSection`, `FunnelSection`, `InsightsView`, `AppRow`, `AppListOptions`, `AppDetailView`, `AppReviewsSection`, `AccountsList`, the charts, `AppIconView`). Configured by the `AppSalesKit` dict (App Group, Keychain service, Google client ID) in all four targets' Info.plists; each `AppIntentsPackage` includes `AppSalesKitPackage`. Change sales features in the package, not here.
- **AI usage lives in [AIUsageKit](https://github.com/256Arts/AIUsageKit)** (`Repos/AIUsageKit`; its AGENTS.md has the details) — Claude/Codex rate limits: sign-ins, fetching (`AIAssistants.shared`), the App Group cache, `AIUsageSection`, `AIUsageSignInSheet`, `AIUsageWidget`, the Mac menu bar extra (`AIUsageMenuBar`, `DockIcon`, `LoginItem`), and `GetAIUsageIntent` (product `AIUsageKitIntents`, main app only). Configured by the `AIUsageKit` dict in the app's, `Widgets`', and `Watch Widgets`' Info.plists (same App Group and Keychain service as the rest of the app). App Sales hosts it: `HomeView` shows the section and presents the sign-in sheet, `AccountsList` connects and disconnects, `AppSalesApp` inserts the `MenuBarExtra` and refreshes once a minute while active, and each target's `AppIntentsPackage` includes the package's. Change the AI usage feature in the package, not here.

**App targets**
- `App Sales/` — the main app. `AppSalesApp` is the `@main` entry; `HomeView` is the root: a `NavigationSplitView` whose sidebar is a Summary row (the stats, chart, insights, and AI usage) above the app list, each app opening `AppDetailView`; a phone opens on the Summary, the list one step back. `HomeView` composes AppSalesKit's sections and adds the ad and `AIUsageSection`; `SalesDataLoader` owns the fetch-and-hold-the-result cycle both it and the watch's `WatchHomeView` display.
- `AppSalesApp` (macOS) inserts AIUsageKit's `.window`-style `MenuBarExtra` only while `AIUsageDefaultsKey.menuBarExtra` is set, tells `DockIcon` about the main window, and keeps the `AppDelegate` that stops the app quitting with the extra up.
- `AppSalesCommands` (in `AppSalesApp.swift`) is the menu bar: Accounts… (⌘,) in place of Settings, Refresh (⌘R), the account picker and `AppListOptions` in View, the 256 Arts links as Help. It reaches the focused window through the `homeCommands` focused value `HomeView` publishes.
- `App Sales/Intents/` — App Intents and App Shortcuts (`GetPerformanceSummaryIntent`, `GetAppSummariesIntent`, `AppSalesShortcuts`, which also offers AIUsageKit's `GetAIUsageIntent`), so Siri, Spotlight, and `shortcuts run` can read sales and AI limits without the UI. Main app target only: the folder is listed in the `WidgetsExtension` membership exceptions so the extension does not register a second copy of the shortcuts. `SalesIntentData` is the one place an intent resolves an account and fetches, and `SalesPeriod` supplies the reported window plus the window it is compared against.
- `Widgets/` — the WidgetKit extension for iOS, macOS, and visionOS. Two files are shared with the watch's extension: `WidgetProvider.swift` (`WidgetPreferences`, the `AppIntentTimelineProvider`, `ACStatEntry`) and `AccessorySummary.swift` (the accessory-family views). Timeline refresh cadence is tuned to when App Store Connect reports become available (~5am in each region). `Widgets.swift` is the `@main` widget; its home screen views are `SummarySmall`, `SummaryWithChart`, and `ErrorWidget`.
  - `Widgets.swift` is a `WidgetBundle` of two widgets: `Widgets` (sales, kind `Widgets`) and AIUsageKit's `AIUsageWidget` (kind `AIUsage`).
  - **Accessory families are conditional.** `WidgetFamily` has no accessory cases on macOS or visionOS, so all of `AccessorySummary.swift` sits inside `#if os(iOS) || os(watchOS)` and `Widgets.supportedFamilies` adds them only on iOS. `.accessoryCorner` is watchOS-only even within that.
- `App Sales Watch App/` — the watchOS app. Standalone: accounts arrive over the iCloud-synchronized Keychain and it fetches from App Store Connect itself, so there is no WatchConnectivity session and nothing to set up on the watch beyond picking an account. `WatchHomeView` is the root; `WatchAccountPicker` is read-only, because an App Store Connect private key is not something anyone types on a watch.
- `Watch Widgets/` — the watchOS complications, a `WidgetBundle` of the sales complications and AIUsageKit's `AIUsageWidget`: the same `Provider` and the same `AccessorySummary` views as the iPhone's Lock Screen widgets, declaring the fourth family (`.accessoryCorner`) on top. `Provider.recommendations()` (watchOS-only, required by `AppIntentTimelineProvider` there) offers one gallery option per Keychain account.

**Screenshots.** `.screenshots.conf` drives the shared `screenshots` runner in `Repos/Scripts`, over `iphone ipad mac vision watch`. `App Sales UITests/ScreenshotTests.swift` is the *one* test for all five: the watch target (`App Sales Watch UITests`, on the `Screenshots Watch` scheme, because a UI test bundle's platform comes from the app it is bound to) compiles the same file. It waits on the `Summary.Proceeds` accessibility identifier, which both `HomeView` and `WatchHomeView` put on their proceeds figure — keep it on any home screen you add — then (off the watch) opens the `AppRow.<name>` row for the demo best seller and waits on `AppDetail.Name`. `ScreenshotMode.prepareLaunch()` is what every `@main` calls at launch. The leading iPhone/iPad/Mac slots are widget shots (`WIDGET_SHOTS`, made by the shared `widget-screenshots`): `WidgetShots.swift` (main app only) draws the tiles under `-widgetShots` — the widgets on iOS, the menu bar extra on macOS, whose open panel (`glass:` in `WIDGET_SHOTS`) is laid on real Liquid Glass over the finished shot by `renderGlass()` — which is why the `Widgets` folder is also in the app target, minus `Widgets.swift`, `WidgetProvider.swift`, `ErrorWidget.swift`.

### Key cross-cutting conventions
- **App Group + Keychain are the integration seam** between app and widget. The shared cache lives in the App Group; credentials live in the synchronizable Keychain. Code that touches data freshness usually needs a `WidgetCenter.shared.reloadAllTimelines()` call (guarded by `#if canImport(WidgetKit)`).
- **Multiplatform** code branches with `#if os(macOS)` / `os(visionOS)` / `os(watchOS)` / `canImport(UIKit)` rather than separate files — keep platform forks inline and minimal. Note `canImport(UIKit)` is *true* on watchOS but most of UIKit is not, so it is not a stand-in for "iOS".
- `UserDefaults.shared` (App-Group-scoped) holds lightweight prefs (`includeRedownloads`, `homeSelectedKey`, …); keys are centralized in AppSalesKit's `UserDefaults.Key` (`appLaunchCount`, app-only, is added in `ExperienceManager.swift`).
- The **demo account path** (`Account.demoAccount` / `ACData.example`) is the way to exercise the UI without real credentials — preserve it when refactoring the fetch pipeline.

## Dependencies (SwiftPM, resolved in the Xcode project)
`AppSalesKit` (256 Arts' own; everything sales — see above, it brings `appstoreconnect-swift-sdk`, `GzipSwift`, `SwiftCSV`, `KeychainAccess`), `AIUsageKit` (256 Arts' own; AI usage — see above), `AdmobSwiftUI` (iOS only — a native ad above the Summary's AI usage; every use sits behind `#if canImport(AdmobSwiftUI)`, and `ExperienceManager` holds it, and the tracking prompt, back until the reader is past the first review request).
