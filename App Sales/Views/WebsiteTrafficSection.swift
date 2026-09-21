import SwiftUI

/// The home screen's website traffic: views of each app's page on the developer's own site, from
/// Google Analytics, beside its downloads — how many people read about an app against how many get it.
///
/// Connecting Google Analytics and picking the website happen in Accounts, beside every other
/// sign-in; this section only reports.
struct WebsiteTrafficSection: View {

    let apps: [AppPerformanceSummary]
    /// Owned by the list, which presents the page editor: an alert inside a `List` section is
    /// handed to every row, and none of them present it.
    @Binding var editingApp: AppPerformanceSummary?

    @State private var googleAnalytics = GoogleAnalytics.shared
    @State private var traffic: [String: WebPageTraffic] = [:]
    @State private var error: Error?

    private var appsWithPages: [AppPerformanceSummary] {
        apps.filter { googleAnalytics.pageURLs[$0.appleID] != nil }
    }

    private var appsWithoutPages: [AppPerformanceSummary] {
        apps.filter { googleAnalytics.pageURLs[$0.appleID] == nil }
    }

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
                    ForEach(appsWithPages) { app in
                        Button {
                            editingApp = app
                        } label: {
                            WebsiteTrafficRow(app: app, traffic: traffic[app.appleID])
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if let url = googleAnalytics.pageURLs[app.appleID] {
                                Link(destination: url) {
                                    Label("Open Page", systemImage: "safari")
                                }
                            }
                            Button("Edit Page", systemImage: "pencil") {
                                editingApp = app
                            }
                            Button("Remove Page", systemImage: "trash", role: .destructive) {
                                googleAnalytics.setPageURL(nil, for: app.appleID)
                            }
                        }
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                googleAnalytics.setPageURL(nil, for: app.appleID)
                            }
                        }
                    }

                    if !appsWithoutPages.isEmpty {
                        Menu {
                            ForEach(appsWithoutPages) { app in
                                Button(app.name) {
                                    editingApp = app
                                }
                            }
                        } label: {
                            Label("Add App Page", systemImage: "plus")
                        }
                        .menuIndicator(.hidden)
                    }
                }

                if let error {
                    Text(error.localizedDescription)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Website", systemImage: "safari")
            } footer: {
                if let property = googleAnalytics.property, !appsWithPages.isEmpty {
                    Text("Page views over the last 30 days, from \(property.name), beside downloads.")
                }
            }
            .task(id: TrafficQuery(property: googleAnalytics.property, pageURLs: googleAnalytics.pageURLs)) {
                await loadTraffic()
            }
        }
    }

    /// What the traffic depends on, so it reloads when the website or any app's page changes.
    private struct TrafficQuery: Equatable {
        let property: GoogleAnalyticsProperty?
        let pageURLs: [String: URL]
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

/// One app's page views against its downloads.
private struct WebsiteTrafficRow: View {

    let app: AppPerformanceSummary
    let traffic: WebPageTraffic?

    var body: some View {
        HStack {
            AppIconView(app: app, length: 24)

            Text(app.name)

            Spacer()

            Group {
                if let traffic {
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

extension View {
    /// Asks for the web address of the page about `app`, the one `WebsiteTrafficSection` counts
    /// views of. Attach it outside the `List` the section sits in.
    func websitePageEditor(for app: Binding<AppPerformanceSummary?>) -> some View {
        modifier(WebsitePageEditor(app: app))
    }
}

private struct WebsitePageEditor: ViewModifier {

    @Binding var app: AppPerformanceSummary?

    @State private var googleAnalytics = GoogleAnalytics.shared
    @State private var pageURLText = ""

    func body(content: Content) -> some View {
        content
            .alert("App Page", isPresented: Binding(get: { app != nil }, set: { if !$0 { app = nil } }), presenting: app) { app in
                TextField("https://example.com/app", text: $pageURLText)
                    .textContentType(.URL)
                    #if canImport(UIKit)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                Button("Save") {
                    googleAnalytics.setPageURL(pageURL, for: app.appleID)
                }
                Button("Cancel", role: .cancel) { }
            } message: { app in
                Text("The page about \(app.name) on your website.")
            }
            .onChange(of: app?.appleID) {
                pageURLText = app.flatMap { googleAnalytics.pageURLs[$0.appleID]?.absoluteString } ?? ""
            }
    }

    /// Typed without a scheme reads as a web address rather than a relative path.
    private var pageURL: URL? {
        let text = pageURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return URL(string: text.contains("://") ? text : "https://" + text)
    }
}
