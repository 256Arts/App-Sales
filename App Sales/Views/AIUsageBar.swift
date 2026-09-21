import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

/// How much of one rate limit window is gone — or left — as a bar that warms as it fills.
///
/// Every surface that draws usage draws this: the home screen section, the widgets, the watch's
/// rectangular complication, and the Mac's menu bar extra. They differ only in whether there is room
/// for the reset line beneath it, which is what `showsReset` is for.
struct AIUsageBar: View {

    let title: LocalizedStringKey
    let limit: AIUsageLimit?

    var display: AIUsageDisplay = .current
    /// The accessory families and the small widget have no room for a second line per bar.
    var showsReset = true

    var body: some View {
        if let limit {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)

                    Spacer()

                    Text(display.percentage(of: limit))
                        .monospacedDigit()
                }

                AIUsageTrack(fraction: display.fraction(of: limit), tint: display.tint(for: limit))

                if showsReset, let resetsAt = limit.resetsAt, resetsAt > .now {
                    display.resetText(resetsAt)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(display.summary(of: limit)))
        }
    }
}

/// The bar on its own: a faint track and a fill.
///
/// Drawn rather than a `ProgressView`, because a tinted widget flattens a `ProgressView`'s track and
/// fill into one solid colour, so the bar reads as full whatever the figure. Here the track keeps its
/// transparency and only the fill is accented. The menu bar label draws the same bar under its text.
struct AIUsageTrack: View {

    let fraction: Double
    var tint: Color = .accentColor
    var height: CGFloat = 4

    var body: some View {
        Capsule()
            .fill(.primary.opacity(0.2))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint)
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? height : 0))
                        #if canImport(WidgetKit)
                        .widgetAccentable()
                        #endif
                }
            }
            .frame(height: height)
    }
}

/// One assistant as a block: who it is, which plan, and where both windows stand.
///
/// The shape the surfaces without a List use — the home screen widget, and the Mac's menu bar
/// extra — where the two bars need a heading of their own rather than a row around them.
struct AIUsageColumn: View {

    let usage: AIUsage
    var display: AIUsageDisplay = .current

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: usage.assistant.systemImage)
                    .foregroundStyle(.secondary)

                Text(usage.assistant.name)
                    .fontWeight(.semibold)

                if let plan = usage.plan {
                    Text(plan)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            AIUsageBar(title: "5 Hours", limit: usage.fiveHour, display: display)
            AIUsageBar(title: "Week", limit: usage.week, display: display)

            Spacer(minLength: 0)
        }
        .font(.caption2)
    }
}

#Preview {
    List {
        AIUsageBar(title: "5 Hours", limit: AIUsage.examples[0].fiveHour)
        AIUsageBar(title: "Week", limit: AIUsage.examples[0].week)
    }
    .font(.footnote)
}
