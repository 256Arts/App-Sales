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
    @AppStorage(UserDefaults.Key.aiUsageMenuBarStyle, store: UserDefaults.shared) private var style: AIUsageMenuBarStyle = .ring
    @AppStorage(UserDefaults.Key.aiUsageMenuBarHidesUnreachable, store: UserDefaults.shared) private var hidesUnreachable = false
    @State private var opensAtLogin = LoginItem.isEnabled

    /// The oldest reading on screen, since that is how stale the window as a whole is.
    private var lastRefresh: Date? {
        usage.map(\.fetched).min()
    }

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

                Group {
                    if refreshing {
                        Text("Updating…")
                    } else if let lastRefresh {
                        Text("Updated \(Text(.currentDate, format: .reference(to: lastRefresh, allowedFields: [.day, .hour, .minute, .second], maxFieldCount: 1)))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

                Spacer()

                Menu {
                    AIUsageOptions()

                    Picker("Menu Bar Progress", selection: $style) {
                        ForEach(AIUsageMenuBarStyle.allCases) { style in
                            Text(style.name)
                                .tag(style)
                        }
                    }

                    Toggle("Hide Irrelevant Limits", isOn: $hidesUnreachable)

                    // Here and not in the app's options: opening at login is only worth it for the
                    // menu bar extra, and without it is a window in the reader's face every morning.
                    Toggle("Open at Login", isOn: Binding {
                        opensAtLogin
                    } set: { newValue in
                        // System Settings can refuse, so the toggle follows what the status ended up as.
                        opensAtLogin = LoginItem.setEnabled(newValue)
                    })

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

/// Whether the menu bar draws each window's progress as a ring beside its countdown, or as a line
/// beneath it.
enum AIUsageMenuBarStyle: String, CaseIterable, Identifiable, Sendable {
    case ring
    case line

    var id: String { rawValue }

    var name: String {
        switch self {
        case .ring: String(localized: "Ring")
        case .line: String(localized: "Underline")
        }
    }
}

/// What sits in the menu bar itself: the assistant closest to running out, with both of its windows
/// — how far through each is, and how long until it empties.
///
/// This is also what keeps the figure fresh with no window open. The label exists only while the
/// extra is inserted, so its task is the refresh that lives exactly as long as the menu bar item —
/// App Sales opening at login and sitting up here all day would otherwise show whatever the last
/// widget timeline happened to fetch, which on a Mac with no widget placed could be hours old.
struct AIUsageMenuBarLabel: View {

    @State private var usage: [AIUsage] = AIUsageCache.all()
    @State private var lastRefresh: Date = .distantPast
    @State private var glyph = NSImage()

    @AppStorage(UserDefaults.Key.aiUsageMetric, store: UserDefaults.shared) private var metric: AIUsageMetric = .used
    @AppStorage(UserDefaults.Key.aiUsageTimeStyle, store: UserDefaults.shared) private var timeStyle: AIUsageTimeStyle = .relative
    @AppStorage(UserDefaults.Key.aiUsageMenuBarStyle, store: UserDefaults.shared) private var style: AIUsageMenuBarStyle = .ring
    @AppStorage(UserDefaults.Key.aiUsageMenuBarHidesUnreachable, store: UserDefaults.shared) private var hidesUnreachable = false

    @Environment(\.displayScale) private var displayScale

    /// The limits the label draws — with `hidesUnreachable`, only the ones that can still run out
    /// before the other does. Never both: with the week out of reach, the five hours are what bite.
    private var shown: [AIUsage] {
        guard hidesUnreachable else { return usage }
        return usage.map { usage in
            let week = usage.canReachWeek() ? usage.week : nil
            return AIUsage(
                assistant: usage.assistant,
                plan: usage.plan,
                fiveHour: week == nil || usage.canReachFiveHour ? usage.fiveHour : nil,
                week: week,
                fetched: usage.fetched)
        }
    }

    private var headline: AIUsage? {
        shown.max { ($0.tightestLimit?.used ?? 0) < ($1.tightestLimit?.used ?? 0) }
    }

    private var display: AIUsageDisplay {
        AIUsageDisplay(metric: metric, timeStyle: timeStyle)
    }

    /// A menu bar extra's label draws only text and images, so the rings and lines are rendered to a
    /// template image — which is also what lets the menu bar tint it for a light or dark wallpaper.
    ///
    /// Rendered into state rather than in `body`: an `ImageRenderer` run during the label's update
    /// asks the menu bar extra for another update, and a fresh image each time never settles.
    private func renderGlyph() {
        let renderer = ImageRenderer(content: AIUsageMenuBarGlyph(usage: headline, display: display, style: style))
        renderer.scale = displayScale
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        glyph = image
    }

    private var accessibilityLabel: String {
        guard let headline, let limit = headline.tightestLimit else { return String(localized: "AI Usage") }
        return "\(headline.assistant.name) \(display.summary(of: limit))"
    }

    var body: some View {
        Image(nsImage: glyph)
            .accessibilityLabel(accessibilityLabel)
            .onChange(of: GlyphInputs(usage: shown, display: display, style: style, scale: displayScale)) {
                renderGlyph()
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
                // Also what redraws the countdowns each minute between refreshes.
                renderGlyph()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Everything the glyph is drawn from, so it is redrawn when any of it changes.
    private struct GlyphInputs: Equatable {
        let usage: [AIUsage]
        let display: AIUsageDisplay
        let style: AIUsageMenuBarStyle
        let scale: CGFloat
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

/// The drawing the menu bar label renders: the assistant's symbol, then the five-hour window and the
/// week, each as its progress and its countdown. Monochrome, since it becomes a template image.
private struct AIUsageMenuBarGlyph: View {

    let usage: AIUsage?
    let display: AIUsageDisplay
    let style: AIUsageMenuBarStyle

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: usage?.assistant.systemImage ?? "gauge.with.dots.needle.33percent")

            if let usage {
                window(usage.fiveHour)
                window(usage.week)
            }
        }
        .font(.system(size: style == .line ? 11 : 12, weight: .medium))
        .monospacedDigit()
        .fixedSize()
        .frame(height: 18)
    }

    @ViewBuilder
    private func window(_ limit: AIUsageLimit?) -> some View {
        if let limit {
            let countdown = limit.resetsAt.map { display.countdown(to: $0) }

            switch style {
            case .ring:
                HStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .stroke(.primary.opacity(0.25), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: display.fraction(of: limit))
                            .stroke(.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 11, height: 11)

                    if let countdown {
                        Text(countdown)
                    }
                }
            case .line:
                // A window nobody has entered has no countdown; the line still needs something to
                // sit under.
                // At least wide enough that a few percent of progress shows as more than a dot, even
                // under a countdown as short as "3d".
                Text(countdown ?? display.percentage(of: limit))
                    .frame(minWidth: 28)
                    .padding(.bottom, 4)
                    .overlay(alignment: .bottom) {
                        AIUsageTrack(fraction: display.fraction(of: limit), tint: .primary, height: 2)
                    }
            }
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
