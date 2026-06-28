# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

App Sales is a multiplatform SwiftUI app (iOS, macOS, visionOS) that displays App Store Connect sales/proceeds data and provides a WidgetKit extension showing the same summaries. It's a fork of "AC Widget by NO-COMMENT" (MIT, see the `AC Widget by NO-COMMENT` file header that SwiftLint enforces), now maintained by 256 Arts.

## Build & Test

There is no Swift Package manifest, Makefile, or CI — this is an Xcode project driven by `App Sales.xcodeproj`.

```bash
# Build the app (choose a -destination appropriate for your goal)
xcodebuild -project "App Sales.xcodeproj" -scheme "App Sales" build

# Build the widget extension
xcodebuild -project "App Sales.xcodeproj" -scheme "WidgetsExtension" build
```

There is **no test target** — do not look for or invent `xcodebuild test` workflows. Verify changes by building and running. SwiftLint is configured (`.swiftlint.yml`) and runs as a build phase if installed; note `force_unwrapping` is an **error**, not a warning, and every `.swift` file must start with the `//  <name>.swift` / `//  AC Widget by NO-COMMENT` header.

Schemes: `App Sales` (main app), `WidgetsExtension` (widget). Platforms: iOS, macOS, visionOS.

## Architecture

The data flow is a one-way pipeline from the App Store Connect API to SwiftUI views and widgets:

**`API/` — networking and the data model (shared by app + widget)**
- `Account` — credentials for one App Store Connect API key (issuerID, privateKeyID, privateKey, vendorNumber). `id` is the privateKeyID. Also conforms to `AppEntity` so the widget configuration intent can pick an account. `Account.demoAccount` short-circuits the whole pipeline to return `ACData.example` mock data.
- `AccountManager` — `@Observable` singleton (`AccountManager.shared`) that persists `[Account]` in the **Keychain** (service `com.jaydenirwin.appsales`, iCloud-synchronizable), *not* UserDefaults despite some method-name wording. Injected into the view tree via `.environment(...)`. Mutations call `WidgetCenter.reloadAllTimelines()`.
- `AppStoreConnectAPI` — the core fetcher. `getData(...)` is the entry point. It uses `AvdLee/appstoreconnect-swift-sdk` to download **daily SALES summary reports** (one request per missing day, gzipped TSV), gunzips them (`GzipSwift`), parses the TSV (`SwiftCSV`) into `[Event]`, converts currency, then enriches with app metadata via the public **iTunes lookup API** (`itunes.apple.com/lookup`). Has two layers of caching: in-memory memoization (`lastData`, 5-min TTL, keyed by `Account`) and on-disk cache via `ACDataCache`. HTTP status codes are mapped to `APIError` cases (401→invalidCredentials, 429→exceededLimit, 403→wrongPermissions, 404→noDataAvailable).
- `ACData` — the parsed dataset: `[Event]` + `[ACApp]` + a `displayCurrency`. All the aggregation/analytics logic lives here as `getRawData`/`getDevices`/`getChange`/`getPerformanceSummary`/`getAppSummaries`, sliced by `InfoType` (`.proceeds`, `.downloads`, `.updates`, `.iap`). Currency conversion is non-destructive via `changeCurrency(to:)`.
- `ACDataCache` — JSON file (`cache.json`) in the **App Group container** (`group.com.jaydenirwin.appsales`), which is how the app and widget share fetched data. Merges new entries with cached ones and prunes to the last ~35 days.
- `Event` — one row of a sales report. `ACApp` — app metadata + icon caching. `CurrencyConverter` — exchange-rate fetch/convert. `PerformanceSummary` — the 30-day-vs-prior-30-day rollup the widget displays.

**App targets**
- `App Sales/` — the main app. `AppSalesApp` is the `@main` entry; `HomeView` is the root, with `Views/` holding the account management UI (`AccountsList`, `NewAccountView`, `AccountDetailView`) and charts (`DownloadsAndProceedsChart`).
- `Widgets/` — the WidgetKit extension. `Widgets.swift` defines the `@main` widget, its `AppIntentTimelineProvider`, and `WidgetPreferences` (the configuration intent that selects an `Account`). Timeline refresh cadence is tuned to when App Store Connect reports become available (~5am in each region). Widget views (`SummarySmall`, `SummaryWithChart`, `ErrorWidget`) render a `PerformanceSummary`.

### Key cross-cutting conventions
- **App Group + Keychain are the integration seam** between app and widget. The shared cache lives in the App Group; credentials live in the synchronizable Keychain. Code that touches data freshness usually needs a `WidgetCenter.shared.reloadAllTimelines()` call (guarded by `#if canImport(WidgetKit)`).
- **Multiplatform** code branches with `#if os(macOS)` / `os(visionOS)` / `canImport(UIKit)` rather than separate files — keep platform forks inline and minimal.
- `UserDefaults.shared` (App-Group-scoped) holds lightweight prefs (`includeRedownloads`, `homeSelectedKey`, `appLaunchCount`); keys are centralized in `UserDefaults.Key`.
- The **demo account path** (`Account.demoAccount` / `ACData.example`) is the way to exercise the UI without real credentials — preserve it when refactoring the fetch pipeline.

## Dependencies (SwiftPM, resolved in the Xcode project)
`appstoreconnect-swift-sdk` (API client), `GzipSwift` (decompress reports), `SwiftCSV` (parse TSV), `KeychainAccess` (credential storage).
