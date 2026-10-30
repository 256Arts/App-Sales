import SwiftUI
import Charts

/// One slice of a pie: a device, a region, or a source of income, and how much came from it.
struct PieShare: Identifiable {
    let name: String
    let badge: Badge
    let color: Color
    let value: Double

    var id: String { name }

    /// What stands for the share on its slice: an SF Symbol, or an emoji such as a flag.
    enum Badge {
        case symbol(String)
        case emoji(String)
    }
}

/// A share's symbol or emoji, at the current font size.
struct PieShareBadge: View {

    let badge: PieShare.Badge

    var body: some View {
        switch badge {
        case .symbol(let name):
            Image(systemName: name)
        case .emoji(let emoji):
            Text(verbatim: emoji)
        }
    }
}

/// Shares as a donut, each slice in its share's colour and marked with its badge, unless it is
/// too thin to hold one.
struct SharePie: View {

    let shares: [PieShare]

    private static let innerRadius = 0.55

    private var total: Double {
        shares.reduce(0) { $0 + $1.value }
    }

    var body: some View {
        Chart(shares) { share in
            SectorMark(angle: .value("Share", share.value), innerRadius: .ratio(Self.innerRadius), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(by: .value("Name", share.name))
                .accessibilityLabel(share.name)
                .accessibilityValue(Text(share.value / max(total, .leastNonzeroMagnitude), format: .percent.precision(.fractionLength(0))))
        }
        .chartForegroundStyleScale(domain: shares.map(\.name), range: shares.map(\.color))
        .chartLegend(.hidden)
        // Placed by hand: an overlay annotation sits out by the ring's outer edge, not across its middle.
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    let radius = min(frame.width, frame.height) / 2 * (1 + Self.innerRadius) / 2
                    ForEach(badges, id: \.share.id) { badge in
                        PieShareBadge(badge: badge.share.badge)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .position(
                                x: frame.midX + radius * sin(badge.angle),
                                y: frame.midY - radius * cos(badge.angle))
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// The slices wide enough to hold a badge, each with the angle through its middle, clockwise
    /// from the top, where the chart starts.
    private var badges: [(share: PieShare, angle: Double)] {
        var start = 0.0
        return shares.compactMap { share in
            let fraction = share.value / max(total, .leastNonzeroMagnitude)
            defer { start += fraction }
            return fraction >= 0.05 ? (share, (start + fraction / 2) * 2 * .pi) : nil
        }
    }
}

/// The last 30 days' income by source, downloads by device, and downloads by region, as cards
/// in one horizontally scrolling row: every app's on the Summary, one app's on its detail page.
/// A pie with nothing to divide is left out, and one with a single slice too, as a full circle says
/// nothing.
struct SharePiesSection: View {

    let data: ACData
    var filteredApps: [ACApp] = []

    private var cards: [SharePieCard] {
        [
            SharePieCard(title: "Income by Source", shares: data.incomeBySource(filteredApps: filteredApps), value: .currency),
            SharePieCard(title: "Downloads by Device", shares: data.downloadsByDevice(filteredApps: filteredApps), value: .count),
            SharePieCard(title: "Downloads by Region", shares: data.downloadsByRegion(filteredApps: filteredApps), value: .count)
        ]
        .filter { $0.shares.count > 1 }
    }

    var body: some View {
        let cards = cards
        if !cards.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(cards.enumerated()), id: \.element.title) { index, card in
                            if index > 0 {
                                Divider()
                                    .padding(.horizontal, 16)
                            }
                            card
                                // Room for three where it fits, else enough of the next to show it scrolls.
                                .containerRelativeFrame(.horizontal) { length, _ in
                                    length >= 720 ? (length - 66) / 3 : min(length * 0.72, 300)
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .contentMargins(.vertical, 16, for: .scrollContent)
                .listRowInsets(EdgeInsets())
            }
        }
    }
}

/// A pie with a title above and a legend beneath giving each share's figure, since a badge does
/// not name its share on its own and a slice alone does not say how much.
struct SharePieCard: View {

    let title: String
    let shares: [PieShare]
    let value: Value

    enum Value {
        case currency
        case count
    }

    init(title: LocalizedStringResource, shares: [PieShare], value: Value) {
        self.title = String(localized: title)
        self.shares = shares
        self.value = value
    }

    /// Whole units: cents only crowd the names out of a legend.
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private func figure(_ share: PieShare) -> String {
        switch value {
        case .currency: Self.currencyFormatter.string(from: NSNumber(value: share.value)) ?? ""
        case .count: Int(share.value).formatted()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            SharePie(shares: shares)
                .frame(height: 140)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(shares) { share in
                    HStack(spacing: 6) {
                        PieShareBadge(badge: share.badge)
                            .foregroundStyle(share.color)
                            .frame(width: 20)
                        Text(share.name)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        Text(figure(share))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Where proceeds come from.
enum IncomeSource: CaseIterable {
    case paidApps
    case subscriptions
    case inAppPurchases
    case ads

    init?(_ type: EventType) {
        switch type {
        case .download, .redownload: self = .paidApps
        case .subscription: self = .subscriptions
        case .iap, .restoredIap: self = .inAppPurchases
        case .ad: self = .ads
        case .update, .unknown: return nil
        }
    }

    var share: (Double) -> PieShare {
        { PieShare(name: name, badge: .symbol(symbol), color: color, value: $0) }
    }

    var name: String {
        switch self {
        case .paidApps: String(localized: "Paid Apps")
        case .subscriptions: String(localized: "Subscriptions")
        case .inAppPurchases: String(localized: "In-App Purchases")
        case .ads: String(localized: "Ads")
        }
    }

    var symbol: String {
        switch self {
        case .paidApps: "square.and.arrow.down"
        case .subscriptions: "repeat"
        case .inAppPurchases: "cart.fill"
        case .ads: "megaphone.fill"
        }
    }

    var color: Color {
        switch self {
        case .paidApps: .blue
        case .subscriptions: .purple
        case .inAppPurchases: .orange
        case .ads: .green
        }
    }
}

/// The App Store's own regions, the ones App Store Connect groups its storefronts under.
enum SalesRegion: CaseIterable {
    case unitedStatesAndCanada
    case europe
    case asiaPacific
    case latinAmerica
    case africaMiddleEastAndIndia
    case unknown

    /// Sorts an ISO country code by the UN region Foundation knows it to sit in.
    init(countryCode: String) {
        // Reports have used UK for the United Kingdom, which is not its ISO code.
        let region = Locale.Region(countryCode == "UK" ? "GB" : countryCode)
        let subregion = region.containingRegion?.identifier
        switch region.continent?.identifier {
        case "019" where subregion == "021":
            self = .unitedStatesAndCanada
        case "019":
            self = .latinAmerica
        case "150":
            self = .europe
        case "002":
            self = .africaMiddleEastAndIndia
        case "142" where subregion == "145" || region.identifier == "IN":
            self = .africaMiddleEastAndIndia
        case "142", "009":
            self = .asiaPacific
        default:
            self = .unknown
        }
    }

    var name: String {
        switch self {
        case .unitedStatesAndCanada: String(localized: "U.S. and Canada")
        case .europe: String(localized: "Europe")
        case .asiaPacific: String(localized: "Asia Pacific")
        case .latinAmerica: String(localized: "Latin America")
        case .africaMiddleEastAndIndia: String(localized: "Africa, Middle East, and India")
        case .unknown: String(localized: "Other")
        }
    }

    /// A flag to stand for the region: one of its biggest markets', or Europe's own.
    var flag: String {
        switch self {
        case .unitedStatesAndCanada: "🇺🇸"
        case .europe: "🇪🇺"
        case .asiaPacific: "🇯🇵"
        case .latinAmerica: "🇧🇷"
        case .africaMiddleEastAndIndia: "🇮🇳"
        case .unknown: "🌐"
        }
    }

    /// The main colour of the region's flag. The U.S. and Japan both fly red, so Japan takes the
    /// pinker crimson its flag actually is.
    var color: Color {
        switch self {
        case .unitedStatesAndCanada: .red
        case .europe: .blue
        case .asiaPacific: .pink
        case .latinAmerica: .green
        case .africaMiddleEastAndIndia: .orange
        case .unknown: .gray
        }
    }
}

extension SalesRegion {
    func share(downloads: Int = 0) -> PieShare {
        PieShare(name: name, badge: .emoji(flag), color: color, value: Double(downloads))
    }
}

extension ACDevice {
    func share(downloads: Int = 0) -> PieShare {
        PieShare(name: name, badge: .symbol(symbol), color: color, value: Double(downloads))
    }

    var color: Color {
        switch self {
        case .iPhone: .blue
        case .iPad: .purple
        case .desktop: .teal
        case .appleWatch: .pink
        case .appleTV: .indigo
        case .appleVision: .orange
        case .iPod: .mint
        case .unknown: .gray
        }
    }
}

extension ACData {
    /// Last 30 days' downloads by device, most first and "Unknown" (or "Other") last, with the report's device names folded into
    /// the ones App Sales knows. Every app's when `filteredApps` is empty.
    func downloadsByDevice(filteredApps: [ACApp] = []) -> [PieShare] {
        let byDevice = Dictionary(getDevices(.downloads, lastNDays: 30, filteredApps: filteredApps).map { (ACDevice($0.0), Int($0.1)) }, uniquingKeysWith: +)
        return byDevice
            .filter { $0.value > 0 }
            .map { $0.key.share(downloads: $0.value) }
            .slices(foldingInto: ACDevice.unknown.share())
    }

    /// Last 30 days' downloads by App Store region, most first and "Other" last.
    func downloadsByRegion(filteredApps: [ACApp] = []) -> [PieShare] {
        let startDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -30, to: .now) ?? .now
        let byRegion = Dictionary(getEntries(for: .downloads, startDate: startDate, filteredApps: filteredApps).map { (SalesRegion(countryCode: $0.countryCode), $0.units) }, uniquingKeysWith: +)
        return byRegion
            .filter { $0.value > 0 }
            .map { $0.key.share(downloads: $0.value) }
            .slices(foldingInto: SalesRegion.unknown.share())
    }
}

extension ACData {
    /// Last 30 days' proceeds by source, most first, in the display currency. Every source a pie
    /// would draw as a sliver is left out, as there is no "Other" to fold it into.
    func incomeBySource(filteredApps: [ACApp] = []) -> [PieShare] {
        let startDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -30, to: .now) ?? .now
        let bySource = Dictionary(getEntries(for: .proceeds, startDate: startDate, filteredApps: filteredApps)
            .compactMap { entry in IncomeSource(entry.type).map { ($0, Double(entry.proceeds) * Double(entry.units)) } },
                                  uniquingKeysWith: +)
        let total = bySource.values.reduce(0, +)
        return bySource
            .filter { $0.value >= total * 0.02 && $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { $0.key.share($0.value) }
    }
}

extension [PieShare] {
    /// The shares a pie can draw, most first. At the Summary's size, one under 2% is lost to the
    /// slices' insets and corner radius, so it shows as nothing but a wider gap; those fold into `other`, which is left out
    /// in turn if they still come to a sliver together. `other` keeps its own name while at least half of it is its own.
    func slices(foldingInto other: PieShare) -> [PieShare] {
        let total = reduce(0) { $0 + $1.value }
        let isSliver = { (value: Double) in value < total * 0.02 }
        let kept = filter { $0.id != other.id && !isSliver($0.value) }
            .sorted { $0.value > $1.value }
        let rest = total - kept.reduce(0) { $0 + $1.value }
        guard rest > 0, !isSliver(rest) else { return kept }

        let own = filter { $0.id == other.id }.reduce(0) { $0 + $1.value }
        let name = own * 2 >= rest ? other.name : String(localized: "Other")
        return kept + [PieShare(name: name, badge: other.badge, color: other.color, value: rest)]
    }
}
