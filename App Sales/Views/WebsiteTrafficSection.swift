import SwiftUI

/// The home screen's website traffic: views of each app's page on the developer's own site, from
/// Google Analytics, beside its downloads — how many people read about an app against how many get it.
///
/// Connecting Google Analytics and picking the website happen in Accounts, beside every other
/// sign-in; this section only reports.
struct WebsiteTrafficSection: View {

    let apps: [AppPerformanceSummary]

    @State private var googleAnalytics = GoogleAnalytics.shared
    @State private var traffic: [String: WebPageTraffic] = [:]
    @State private var error: Error?
    @State private var editingApp: AppPerformanceSummary?
    @State private var pageURLText = ""

    var body: some View {
        if GoogleAnalytics.isAvailable {
            Section {
                if !googleAnalytics.isConnected {
                    Text("Connect Google Analytics in Accounts to see how many people read about each app on your website, next to how many download it.")
                        .foregroundStyle(.secondary)
                } else if googleAnalytics.property == nil {
                    Text("Choose your website in Accounts to see how many people read about each app on it.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(apps) { app in
                        Button {
                            editingApp = app
                            pageURLText = googleAnalytics.pageURLs[app.appleID]?.absoluteString ?? ""
                        } label: {
                            WebsiteTrafficRow(app: app, traffic: traffic[app.appleID], hasPage: googleAnalytics.pageURLs[app.appleID] != nil)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error {
                    Text(error.localizedDescription)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Website", systemImage: "safari")
            } footer: {
                if let property = googleAnalytics.property {
                    Text("Page views over the last 30 days, from \(property.name). Select an app to set its page.")
                }
            }
            .task(id: TrafficQuery(property: googleAnalytics.property, pageURLs: googleAnalytics.pageURLs)) {
                await loadTraffic()
            }
            .alert("App Page", isPresented: Binding(get: { editingApp != nil }, set: { if !$0 { editingApp = nil } }), presenting: editingApp) { app in
                TextField("https://example.com/app", text: $pageURLText)
                    .textContentType(.URL)
                    #if canImport(UIKit)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                Button("Save") {
                    googleAnalytics.setPageURL(pageURL, for: app.appleID)
                }
                if googleAnalytics.pageURLs[app.appleID] != nil {
                    Button("Remove", role: .destructive) {
                        googleAnalytics.setPageURL(nil, for: app.appleID)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: { app in
                Text("The page about \(app.name) on your website.")
            }
        }
    }

    /// What the traffic depends on, so it reloads when the website or any app's page changes.
    private struct TrafficQuery: Equatable {
        let property: GoogleAnalyticsProperty?
        let pageURLs: [String: URL]
    }

    /// Typed without a scheme reads as a web address rather than a relative path.
    private var pageURL: URL? {
        let text = pageURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return URL(string: text.contains("://") ? text : "https://" + text)
    }

    private func loadTraffic() async {
        // Disconnected, or the website changed away, in Accounts — the last website's views are no longer ours.
        guard googleAnalytics.property != nil else {
            traffic = [:]
            return
        }

        error = nil
        do {
            traffic = try await googleAnalytics.traffic()
        } catch {
            self.error = error
        }
    }
}

/// One app's page views against its downloads, or a prompt to set its page.
private struct WebsiteTrafficRow: View {

    let app: AppPerformanceSummary
    let traffic: WebPageTraffic?
    let hasPage: Bool

    var body: some View {
        HStack {
            AppIconView(app: app, length: 24)

            Text(app.name)

            Spacer()

            Group {
                if !hasPage {
                    Text("Set Page")
                        .foregroundStyle(.tint)
                } else if let traffic {
                    HStack(spacing: 8) {
                        Label(traffic.views.formatted(), systemImage: "eye")
                            .accessibilityLabel("\(traffic.views) page views")
                        Label(app.downloads.formatted(), systemImage: "arrow.down.app")
                            .accessibilityLabel("\(app.downloads) downloads")
                    }
                    .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .font(.footnote)
        }
        .contentShape(.rect)
    }
}
