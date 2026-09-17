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
}
