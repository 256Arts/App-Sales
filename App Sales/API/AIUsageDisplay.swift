import SwiftUI

/// Whether a limit reads as how much of the window is gone, or how much of it is left.
///
/// The same number either way — which one is the useful one depends on what the reader is asking.
/// "61% used" answers "how hard have I been leaning on this"; "39% left" answers "can I start
/// another job before dinner".
enum AIUsageMetric: String, CaseIterable, Identifiable, Sendable {
    case used
    case remaining

    var id: String { rawValue }

    var name: String {
        switch self {
        case .used: String(localized: "Used")
        case .remaining: String(localized: "Left")
        }
    }
}

/// Whether a reset reads as a countdown or as a clock time.
enum AIUsageTimeStyle: String, CaseIterable, Identifiable, Sendable {
    case relative
    case absolute

    var id: String { rawValue }

    var name: String {
        switch self {
        case .relative: String(localized: "Relative")
        case .absolute: String(localized: "Absolute")
        }
    }
}

/// How usage is drawn, and the small amount of formatting that follows from it.
///
/// The choices live in the App Group rather than in any one view, because four surfaces draw the
/// same figures and they must agree: the home screen section, the widgets, the watch complications,
/// and the Mac's menu bar extra. Everything here is a pure function of a limit, so all four share
/// one reading of it instead of each inventing its own.
struct AIUsageDisplay: Equatable, Sendable {

    var metric: AIUsageMetric
    var timeStyle: AIUsageTimeStyle

    static let `default` = AIUsageDisplay(metric: .used, timeStyle: .relative)

    /// What the reader last chose. Read at draw time, because a widget process outlives the change.
    static var current: AIUsageDisplay {
        guard let defaults = UserDefaults.shared else { return .default }

        return AIUsageDisplay(
            metric: defaults.string(forKey: UserDefaults.Key.aiUsageMetric)
                .flatMap(AIUsageMetric.init(rawValue:)) ?? Self.default.metric,
            timeStyle: defaults.string(forKey: UserDefaults.Key.aiUsageTimeStyle)
                .flatMap(AIUsageTimeStyle.init(rawValue:)) ?? Self.default.timeStyle)
    }

    /// The part of the window this reading is about, `0...1` — what a bar or a gauge fills to.
    ///
    /// Clamped, because an assistant that reports going over its limit would otherwise overfill the
    /// ring, and `1 - used` would go negative.
    func fraction(of limit: AIUsageLimit) -> Double {
        let used = min(max(limit.used, 0), 1)
        return metric == .used ? used : 1 - used
    }

    /// That fraction as a percentage, e.g. "61%".
    func percentage(of limit: AIUsageLimit) -> String {
        fraction(of: limit).formatted(.percent.precision(.fractionLength(0)))
    }

    /// Percentage and metric in one line, for the families with no room for a separate label.
    func summary(of limit: AIUsageLimit) -> String {
        "\(percentage(of: limit)) \(metric.name.lowercased())"
    }

    /// When the window empties, phrased the way the reader asked for.
    ///
    /// Absolute times drop the weekday when the reset lands today — a five-hour window nearly always
    /// does, and "Resets Thu 4:30 PM" reads as further off than it is.
    func resetText(_ date: Date) -> Text {
        switch timeStyle {
        case .relative:
            Text("Resets \(date, format: .relative(presentation: .numeric))")
        case .absolute:
            if Calendar.autoupdatingCurrent.isDateInToday(date) {
                Text("Resets \(date, format: .dateTime.hour().minute())")
            } else {
                Text("Resets \(date, format: .dateTime.weekday(.abbreviated).hour().minute())")
            }
        }
    }

    /// When the window empties, in the fewest characters that still say it — "2h 15m", "3d", or
    /// "4:30 PM" when the reader asked for clock times. For the menu bar, which has no room for the
    /// word "Resets".
    ///
    /// Under a day a countdown keeps its minutes: a five-hour window always is, and "2h" rounds away
    /// most of what is worth knowing about it.
    func countdown(to date: Date) -> String {
        switch timeStyle {
        case .relative:
            let seconds = max(date.timeIntervalSinceNow, 0)
            return Duration.seconds(seconds).formatted(.units(
                allowed: [.days, .hours, .minutes],
                width: .narrow,
                maximumUnitCount: seconds < 24 * 60 * 60 ? 2 : 1))
        case .absolute:
            return Calendar.autoupdatingCurrent.isDateInToday(date)
                ? date.formatted(.dateTime.hour().minute())
                : date.formatted(.dateTime.weekday(.abbreviated).hour())
        }
    }

    /// The same three-step reading as a battery: fine, getting low, nearly out.
    ///
    /// Always keyed off how much is *gone*, whichever way round the number is being shown — the
    /// warning is about the window running out, not about which figure is on screen.
    func tint(for limit: AIUsageLimit) -> Color {
        switch limit.used {
        case 0.9...: .red
        case 0.75...: .orange
        default: .accentColor
        }
    }
}

extension AIUsage {

    /// The window closest to running out, which is the one that will actually stop the next job.
    ///
    /// The families with room for only one number show this rather than always showing the
    /// five-hour window: on a heavy week it is the weekly limit that bites first.
    var tightestLimit: AIUsageLimit? {
        [fiveHour, week].compactMap { $0 }.max { $0.used < $1.used }
    }

    /// Roughly how many full five-hour windows one week's limit holds, for both assistants.
    static let fiveHourWindowsPerWeek = 9.0

    /// Whether the five-hour window can still run out before the week does.
    ///
    /// Not when what is left of the week is less than what is left of this window: with 1% of the
    /// week to go, a fresh five hours is not the limit that will stop the next job.
    var canReachFiveHour: Bool {
        guard let fiveHour, let week else { return true }
        // A week that empties before this window does refills first.
        if let weekResets = week.resetsAt, let fiveHourResets = fiveHour.resetsAt, weekResets < fiveHourResets {
            return true
        }
        return (1 - week.used) * Self.fiveHourWindowsPerWeek >= 1 - fiveHour.used
    }

    /// Whether the week can still run out before it resets.
    ///
    /// Not when what is left of it outlasts every five-hour window that fits before the reset, used
    /// to the full — which assumes working around the clock, so a week that could still bite is
    /// never hidden.
    func canReachWeek(at date: Date = .now) -> Bool {
        guard let fiveHour, let week else { return true }
        let weekResets = week.resetsAt ?? date.addingTimeInterval(7 * 24 * 60 * 60)
        // A window nobody has entered starts whenever the next job does.
        let nextWindow = fiveHour.resetsAt ?? date
        let currentWindow = fiveHour.resetsAt == nil ? 0 : max(1 - fiveHour.used, 0)
        let laterWindows = (max(weekResets.timeIntervalSince(nextWindow), 0) / (5 * 60 * 60)).rounded(.up)
        return (currentWindow + laterWindows) / Self.fiveHourWindowsPerWeek > 1 - week.used
    }
}
