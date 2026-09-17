import SwiftUI

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
            ProgressView(value: display.fraction(of: limit)) {
                HStack {
                    Text(title)

                    Spacer()

                    Text(display.percentage(of: limit))
                        .monospacedDigit()
                }
            } currentValueLabel: {
                if showsReset, let resetsAt = limit.resetsAt, resetsAt > .now {
                    display.resetText(resetsAt)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(display.tint(for: limit))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(display.summary(of: limit)))
        }
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
