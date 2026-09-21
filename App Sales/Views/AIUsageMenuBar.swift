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
    @AppStorage(UserDefaults.Key.aiUsageGoal, store: UserDefaults.shared) private var goal: AIUsageGoal = .none
    @AppStorage(UserDefaults.Key.aiUsageMenuBarStyle, store: UserDefaults.shared) private var style: AIUsageMenuBarStyle = .ring
    @AppStorage(UserDefaults.Key.aiUsageHidesUnreachable, store: UserDefaults.shared) private var hidesUnreachable = false
    @State private var opensAtLogin = LoginItem.isEnabled

    @Environment(\.openWindow) private var openWindow

    /// The oldest reading on screen, since that is how stale the window as a whole is.
    private var lastRefresh: Date? {
        usage.map(\.fetched).min()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                if usage.isEmpty {
                    Text(message ?? String(localized: "Sign in to Claude or Codex in App Sales to see your limits here."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        // A Text in a menu bar window truncates to one line without this, however wide
                        // the window is told to be.
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(usage) { usage in
                        AIUsageColumn(usage: usage, display: AIUsageDisplay(metric: metric, timeStyle: timeStyle, goal: goal, hidesUnreachable: hidesUnreachable), showsMetric: true)
                    }
                }
            }
            .padding(12)

            Divider()

            HStack {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await load(maxAge: 0) }
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
                    AIUsageOptions {
                        Picker("Progress Style", selection: $style) {
                            ForEach(AIUsageMenuBarStyle.allCases) { style in
                                Text(style.name)
                                    .tag(style)
                            }
                        }
                    } menuBarItems: {
                        // Here and not in the app's options: opening at login is only worth it for the
                        // menu bar extra, and without it is a window in the reader's face every morning.
                        Toggle("Open at Login", isOn: Binding {
                            opensAtLogin
                        } set: { newValue in
                            // System Settings can refuse, so the toggle follows what the status ended up as.
                            opensAtLogin = LoginItem.setEnabled(newValue)
                        })
                    }

                    Divider()

                    // With no window open there is no Dock icon to click, so this is the way back in.
                    Button("Open App Sales") {
                        if !DockIcon.hasWindow {
                            openWindow(id: AppSalesApp.mainWindowID)
                        }
                        NSApplication.shared.activate()
                    }

                    Button("Quit App Sales") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Label("Options", systemImage: "switch.2")
                }
                // Drawn as a button, so it takes the accessory bar style and matches Refresh's height.
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.accessoryBar)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(width: 260)
        .task { await load() }
    }

    private func load(maxAge: TimeInterval = AIUsageCache.freshness) async {
        // A screenshot run has no sign-ins, so a fetch would clear the examples it started with.
        guard !ScreenshotMode.isActive else { return }

        refreshing = true
        defer { refreshing = false }

        var fetched: [AIUsage] = []
        var failure: String?

        // In turn, not at once: a refresh token used twice gets its family revoked.
        for assistant in assistants.connected {
            do {
                fetched.append(try await assistants.usage(for: assistant, maxAge: maxAge))
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
/// beneath it — or, with reset times hidden, the two lines stacked.
enum AIUsageMenuBarStyle: String, CaseIterable, Identifiable, Sendable {
    case ring
    case line

    var id: String { rawValue }

    var name: String {
        switch self {
        case .ring: String(localized: "Ring")
        case .line: String(localized: "Line")
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
    @State private var glyph = NSImage()

    @AppStorage(UserDefaults.Key.aiUsageMetric, store: UserDefaults.shared) private var metric: AIUsageMetric = .used
    @AppStorage(UserDefaults.Key.aiUsageTimeStyle, store: UserDefaults.shared) private var timeStyle: AIUsageTimeStyle = .relative
    @AppStorage(UserDefaults.Key.aiUsageGoal, store: UserDefaults.shared) private var goal: AIUsageGoal = .none
    @AppStorage(UserDefaults.Key.aiUsageMenuBarStyle, store: UserDefaults.shared) private var style: AIUsageMenuBarStyle = .ring
    @AppStorage(UserDefaults.Key.aiUsageHidesUnreachable, store: UserDefaults.shared) private var hidesUnreachable = false

    @Environment(\.displayScale) private var displayScale

    private var shown: [AIUsage] {
        usage.map(display.relevant)
    }

    private var headline: AIUsage? {
        shown.max { ($0.tightestLimit?.used ?? 0) < ($1.tightestLimit?.used ?? 0) }
    }

    private var display: AIUsageDisplay {
        AIUsageDisplay(metric: metric, timeStyle: timeStyle, goal: goal, hidesUnreachable: hidesUnreachable)
    }

    /// A menu bar extra's label draws only text and images, so the rings and lines are rendered to a
    /// template image — which is also what lets the menu bar tint it for a light or dark wallpaper.
    ///
    /// A template image is one colour, though, and a warning has to be orange. While one is showing,
    /// the glyph is rendered for both appearances instead and drawn from whichever the menu bar is
    /// in at the time, which is the one moment that is known.
    ///
    /// Rendered into state rather than in `body`: an `ImageRenderer` run during the label's update
    /// asks the menu bar extra for another update, and a fresh image each time never settles.
    private func renderGlyph() {
        let content = AIUsageMenuBarGlyph(usage: headline, display: display, style: style)

        guard content.warns else {
            let image = render(content)
            image.isTemplate = true
            glyph = image
            return
        }

        let light = render(content.environment(\.colorScheme, .light))
        let dark = render(content.environment(\.colorScheme, .dark))
        glyph = NSImage(size: light.size, flipped: false) { rect in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            (isDark ? dark : light).draw(in: rect)
            return true
        }
    }

    private func render(_ content: some View) -> NSImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = displayScale
        return renderer.nsImage ?? NSImage()
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
        // Asks the assistants every minute, so the figure moves while the work is being done. A
        // sign-in that fails is retried once per `freshness` instead, rather than every minute.
        .task {
            var retryAt = Date.distantPast
            while !Task.isCancelled {
                if retryAt <= .now, await !refresh() {
                    retryAt = .now.addingTimeInterval(AIUsageCache.freshness)
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
    /// would sign the reader's terminal out. A window that has run out is not asked about again
    /// until it resets, since nothing can change before then. Failures are left to the window,
    /// which can explain them; up here the last good reading stays on screen.
    ///
    /// Returns whether every assistant answered.
    private func refresh() async -> Bool {
        let assistants = AIAssistants.shared
        var succeeded = true

        // In turn, not at once, for the same reason.
        for assistant in assistants.connected {
            do {
                // Half the tick: a reading another process took in the last half minute is as good
                // as one of our own, and anything older is asked for again.
                _ = try await assistants.usage(for: assistant, maxAge: 30)
            } catch {
                succeeded = false
            }
        }
        return succeeded
    }
}

/// The drawing the menu bar label renders: the assistant's symbol, then the five-hour window and the
/// week, each as its progress and its countdown. Monochrome unless a window warns, since it becomes
/// a template image.
struct AIUsageMenuBarGlyph: View {

    let usage: AIUsage?
    let display: AIUsageDisplay
    let style: AIUsageMenuBarStyle

    private static let windows: [AIUsageWindow] = [.fiveHour, .week]

    /// Whether any window is drawn in a warning colour, which a template image cannot show.
    var warns: Bool {
        guard let usage else { return false }
        return Self.windows.contains { window in
            usage[window].flatMap { display.warning(for: $0, in: window) } != nil
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: usage?.assistant.systemImage ?? "gauge.with.dots.needle.33percent")

            if let usage {
                if style == .line, display.timeStyle == .hidden {
                    // With no countdowns to sit under, the lines stack — five hours over the week.
                    VStack(spacing: 3) {
                        ForEach(Self.windows, id: \.self) { window in
                            if let limit = usage[window] {
                                AIUsageTrack(fraction: display.fraction(of: limit), tint: tint(for: limit, in: window), height: 3)
                            }
                        }
                    }
                    .frame(width: 28)
                } else {
                    ForEach(Self.windows, id: \.self) { window in
                        self.window(window, of: usage)
                    }
                }
            }
        }
        .font(.system(size: style == .line ? 11 : 12, weight: .medium))
        .monospacedDigit()
        .fixedSize()
        .frame(height: 18)
    }

    private func tint(for limit: AIUsageLimit, in window: AIUsageWindow) -> Color {
        display.warning(for: limit, in: window) ?? .primary
    }

    @ViewBuilder
    private func window(_ window: AIUsageWindow, of usage: AIUsage) -> some View {
        if let limit = usage[window] {
            let countdown = limit.resetsAt.flatMap { display.countdown(to: $0) }
            let tint = tint(for: limit, in: window)

            switch style {
            case .ring:
                HStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .stroke(.primary.opacity(0.25), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: display.fraction(of: limit))
                            .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
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
                        AIUsageTrack(fraction: display.fraction(of: limit), tint: tint, height: 2)
                    }
            }
        }
    }
}

/// Keeps App Sales out of the Dock while the menu bar extra is all that is running, the way a menu
/// bar utility behaves, and puts it back as soon as a window opens.
@MainActor
enum DockIcon {

    private static var windows = 0
    private static var showsMenuBarExtra = false

    static var hasWindow: Bool { windows > 0 }

    static func windowOpened() {
        windows += 1
        update()
    }

    static func windowClosed() {
        windows = max(windows - 1, 0)
        update()
    }

    static func menuBarExtra(isShown: Bool) {
        showsMenuBarExtra = isShown
        update()
    }

    /// With the extra off, the Dock icon stays whether or not a window is open — otherwise nothing
    /// on screen would lead back to the app.
    private static func update() {
        let policy: NSApplication.ActivationPolicy = windows == 0 && showsMenuBarExtra ? .accessory : .regular
        guard NSApplication.shared.activationPolicy() != policy else { return }
        NSApplication.shared.setActivationPolicy(policy)
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
