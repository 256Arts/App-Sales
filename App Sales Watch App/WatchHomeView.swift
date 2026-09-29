import SwiftUI

/// The watch's home screen: the same 30-day proceeds and downloads the iPhone leads with, sized to
/// be read at a glance, followed by the per-app breakdown.
///
/// The watch app is standalone — accounts reach it through the iCloud-synchronized Keychain
/// `AccountManager` already reads from, and it fetches from App Store Connect itself — so there is
/// nothing to set up here beyond picking which account to show.
struct WatchHomeView: View {

    @State private var loader = SalesDataLoader()

    @Environment(AccountManager.self) private var accountManager

    @AppStorage(UserDefaults.Key.homeSelectedKey, store: UserDefaults.shared) private var keyID: String = ""

    private var selectedAccount: Account? {
        accountManager.getApiKey(apiKeyId: keyID) ?? accountManager.accounts.first
    }

    var body: some View {
        Group {
            if accountManager.accounts.isEmpty {
                noAccount
            } else if let summary = loader.summary {
                salesList(summary)
            } else if let error = loader.error {
                failure(error)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("App Sales")
        .toolbar {
            if !accountManager.accounts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await fetch(useMemoization: false) }
                    }
                }
            }
        }
        .onChange(of: keyID) {
            Task { await fetch(useMemoization: false) }
        }
        .task { await fetch() }
    }

    private func salesList(_ summary: PerformanceSummary) -> some View {
        List {
            Section {
                MetricRow(
                    title: "Proceeds",
                    value: NumberFormatter.currency.string(from: NSNumber(value: summary.proceeds)) ?? "",
                    change: summary.proceedsPercentageChange)
                    // The screenshot walk waits on this before its shot, the same way it does on
                    // the phone, so a capture cannot beat the fetched data onto the screen.
                    .accessibilityIdentifier("Summary.Proceeds")
                MetricRow(
                    title: "Downloads",
                    value: summary.downloads.formatted(),
                    change: summary.downloadsPercentageChange)
            } header: {
                Text("Last 30 Days")
            }

            if !summary.apps.isEmpty {
                Section("Apps") {
                    ForEach(summary.apps) { app in
                        WatchAppRow(app: app)
                    }
                }
            }

            // Below the numbers rather than in the toolbar: switching account is a rare act, and a
            // watch's bar has room for one control — which the refresh button has earned.
            if 1 < accountManager.accounts.count {
                Section {
                    NavigationLink {
                        WatchAccountPicker()
                    } label: {
                        LabeledContent("Account", value: selectedAccount?.name ?? "")
                    }
                }
            }
        }
        .refreshable {
            await fetch(useMemoization: false)
        }
    }

    private var noAccount: some View {
        ContentUnavailableView(
            "No Account",
            systemImage: "person.crop.circle.badge.questionmark",
            description: Text("Add an App Store Connect account in App Sales on your iPhone. It syncs here through iCloud Keychain."))
    }

    private func failure(_ error: APIError) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(error.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Retry") {
                    Task { await fetch(useMemoization: false) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func fetch(useMemoization: Bool = true) async {
        await loader.load(account: selectedAccount, useMemoization: useMemoization)
    }
}

/// One headline number and how it moved against the previous 30 days.
private struct MetricRow: View {

    let title: LocalizedStringKey
    let value: String
    let change: Double

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.negativePrefix = ""
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    // A long currency string should shrink rather than push the arrow off the watch.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer(minLength: 0)

                Label(
                    Self.percentFormatter.string(from: NSNumber(value: change)) ?? "",
                    systemImage: change < 0 ? "arrow.down.forward" : "arrow.up.forward")
                    .font(.caption)
                    .foregroundStyle(change < 0 ? Color.red : Color.green)
                    .labelStyle(.titleAndIcon)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One app's 30-day downloads and proceeds, with its icon.
private struct WatchAppRow: View {

    let app: AppPerformanceSummary

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(app: app, length: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label(app.downloads.formatted(), systemImage: "arrow.down.app")
                    Text(NumberFormatter.currency.string(from: NSNumber(value: app.proceeds)) ?? "")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
    }
}

#Preview {
    NavigationStack {
        WatchHomeView()
    }
    .environment(AccountManager.shared)
}
