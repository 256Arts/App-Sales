import SwiftUI
import Charts
import ImageIO

/// One stat from the home screen's chart, day by day, stacked app by app: what the bar chart
/// becomes when its legend picks a stat.
struct AppTrendsChart: View {

    /// Best first, Other last; drawn the other way round, so the best sit atop the stack.
    let trends: [AppTrend]
    let stat: AppListSort
    let range: Range<Date>

    private static let fallbackColors: [Color] = [.blue, .green, .orange, .purple, .red]

    /// Each app's icon color by ID, filled in as the icons load.
    @State private var iconColors: [String: Color] = [:]

    private func color(of trend: AppTrend, at index: Int) -> Color {
        if trend.isOther { return .gray }
        return iconColors[trend.id] ?? Self.fallbackColors[index % Self.fallbackColors.count]
    }

    var body: some View {
        Chart(trends.reversed()) { trend in
            ForEach(trend.days, id: \.date) { day in
                AreaMark(x: .value("Day", day.date, unit: .day), y: .value(stat.title, day.value))
                    .foregroundStyle(by: .value("App", trend.name))
                    .interpolationMethod(.monotone)
            }
        }
        // The legend reads best first, whatever order the stack is drawn in.
        .chartForegroundStyleScale(
            domain: trends.map(\.name),
            range: trends.indices.map { color(of: trends[$0], at: $0) })
        .chartXScale(domain: range.lowerBound...range.upperBound)
        .chartLegend(position: .bottom, alignment: .leading)
        .task(id: trends.map(\.id)) {
            for trend in trends where !trend.isOther && iconColors[trend.id] == nil {
                if let color = await IconColor.dominant(of: trend.iconURL, cachedAt: trend.cachedIconURL) {
                    iconColors[trend.id] = color
                }
            }
        }
    }
}

/// The color an app icon is known by: its most common saturated hue.
enum IconColor {

    static func dominant(of url: URL?, cachedAt cachedURL: URL?) async -> Color? {
        var data = cachedURL.flatMap { try? Data(contentsOf: $0) }
        if data == nil, let url {
            data = url.isFileURL ? try? Data(contentsOf: url) : try? await URLSession.shared.data(from: url).0
        }
        guard let data else { return nil }
        return dominant(in: data)
    }

    private static func dominant(in data: Data) -> Color? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 24
              ] as CFDictionary) else { return nil }

        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Twelve hue buckets, each weighted by saturation so white and gray backgrounds lose to artwork.
        var weights = [Double](repeating: 0, count: 12)
        var sums = [(r: Double, g: Double, b: Double)](repeating: (0, 0, 0), count: 12)
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 200 {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
            guard maxC > 0.2, delta > 0.15 else { continue }
            let saturation = delta / maxC
            var hue: Double
            switch maxC {
            case r: hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            case g: hue = (b - r) / delta + 2
            default: hue = (r - g) / delta + 4
            }
            if hue < 0 { hue += 6 }
            let bucket = min(11, Int(hue * 2))
            let weight = saturation * saturation
            weights[bucket] += weight
            sums[bucket].r += r * weight
            sums[bucket].g += g * weight
            sums[bucket].b += b * weight
        }
        guard let best = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[best] > 0 else { return nil }
        let total = weights[best]
        return Color(.sRGB, red: sums[best].r / total, green: sums[best].g / total, blue: sums[best].b / total)
    }
}

struct AppTrend: Identifiable {
    let id: String
    let name: String
    let days: [DailyValue]
    var iconURL: URL?
    var cachedIconURL: URL?

    init(app: AppPerformanceSummary, days: [DailyValue]) {
        id = app.appleID
        name = app.name
        iconURL = app.iconURL
        cachedIconURL = app.cachedIconURL
        self.days = days
    }

    /// Every app past the chart's few, summed.
    init(otherDays days: [DailyValue]) {
        id = "Other"
        name = String(localized: "Other")
        self.days = days
    }

    var isOther: Bool { id == "Other" }
}
