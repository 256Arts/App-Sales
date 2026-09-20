#if os(macOS)
import SwiftUI
import ServiceManagement

/// The Mac's menu bar extra: the same usage figures as the widget, in the one place a Mac can show
/// a number without a window being open.
///
/// This is where the figures are worth the most — the work that spends the limits is being done on
/// this machine, a few inches below — so it is also the one surface with a reason to launch at login
/// and sit there. It is off until the reader turns it on, because a menu bar item that installs
/// itself is a menu bar item nobody asked for.
struct AIUsageMenuBar: View {

    @State private var assistants = AIAssistants.shared
    @State private var usage: [AIUsage] = AIUsageCache.all()
    @State private var message: String?
    @State private var refreshing = false

    @AppStorage(UserDefaults.Key.aiUsageMetric, store: UserDefaults.shared) private var metric: AIUsageMetric = .used
    @AppStorage(UserDefaults.Key.aiUsageTimeStyle, store: UserDefaults.shared) private var timeStyle: AIUsageTimeStyle = .relative

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if usage.isEmpty {
                Text(message ?? String(localized: "Connect Claude or Codex in App Sales to see your limits here."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    // A Text in a menu bar window truncates to one line without this, however wide
                    // the window is told to be.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(usage) { usage in
                    AIUsageColumn(usage: usage, display: AIUsageDisplay(metric: metric, timeStyle: timeStyle))
                }
            }

            Divider()

            HStack {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await load(allowingCached: false) }
                }
                .disabled(refreshing)

                Spacer()

                Menu {
                    AIUsageOptions()

                    Divider()

                    Button("Quit App Sales") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis")
                }
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.accessoryBar)
        }
        .padding(12)
        .frame(width: 260)
        .task { await load() }
    }

    private func load(allowingCached: Bool = true) async {
        refreshing = true
        defer { refreshing = false }

        var fetched: [AIUsage] = []
        var failure: String?

        // In turn, not at once: a refresh token used twice gets its family revoked.
        for assistant in assistants.connected {
            do {
                fetched.append(try await assistants.usage(for: assistant, allowingCached: allowingCached))
            } catch {
                if let cached = AIUsageCache.usage(for: assistant) {
                    fetched.append(cached)
                } else if failure == nil {
                    failure = error.localizedDescription
                }
            }
        }

        usage = fetched
        message = fetched.isEmpty ? failure : nil
    }
}

/// What sits in the menu bar itself: the window closest to running out, so the figure on screen is
/// always the one about to stop the next job.
///
/// This is also what keeps the figure fresh with no window open. The label exists only while the
/// extra is inserted, so its task is the refresh that lives exactly as long as the menu bar item —
/// App Sales opening at login and sitting up here all day would otherwise show whatever the last
/// widget timeline happened to fetch, which on a Mac with no widget placed could be hours old.
struct AIUsageMenuBarLabel: View {

    @State private var usage: [AIUsage] = AIUsageCache.all()
    @State private var lastRefresh: Date = .distantPast

    @AppStorage(UserDefaults.Key.aiUsageMetric, store: UserDefaults.shared) private var metric: AIUsageMetric = .used

    private var headline: (AIUsage, AIUsageLimit)? {
        let tightest = usage.compactMap { usage in usage.tightestLimit.map { (usage, $0) } }
        return tightest.max { $0.1.used < $1.1.used }
    }

    var body: some View {
        Group {
            if let (usage, limit) = headline {
                Label(AIUsageDisplay(metric: metric, timeStyle: .relative).percentage(of: limit), systemImage: usage.assistant.systemImage)
            } else {
                Image(systemName: "gauge.with.dots.needle.33percent")
            }
        }
        // Re-reading the cache every minute picks up whatever the app, the widgets, and the menu bar
        // window fetched; asking the assistants happens at most once per `freshness`, so a sign-in
        // that keeps failing is retried on that cadence rather than every minute.
        .task {
            while !Task.isCancelled {
                if lastRefresh.timeIntervalSinceNow < -AIUsageCache.freshness {
                    lastRefresh = .now
                    await refresh()
                }
                usage = AIUsageCache.all()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Through `AIAssistants.shared.usage(for:)` like every other surface, so a reading another
    /// process saved in the last `freshness` is used as it is, and there is never a second fetch of
    /// the same assistant in flight — a refresh token used twice gets its family revoked, which
    /// would sign the reader's terminal out. Failures are left to the window, which can explain
    /// them; up here the last good reading stays on screen.
    private func refresh() async {
        let assistants = AIAssistants.shared

        // In turn, not at once, for the same reason.
        for assistant in assistants.connected {
            _ = try? await assistants.usage(for: assistant)
        }
    }
}

/// Whether macOS starts App Sales at login.
///
/// Only worth offering alongside the menu bar extra: without it, opening at login just puts a window
/// in the reader's face every morning. `SMAppService` is the source of truth — the reader can turn
/// this off in System Settings > General > Login Items, and the toggle has to follow when they do.
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns what the status actually is afterwards, which is not always what was asked for:
    /// a registration the reader has not approved lands on `.requiresApproval`.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Login item change failed", error)
        }
        return isEnabled
    }
}

#Preview {
    AIUsageMenuBar()
}
#endif
