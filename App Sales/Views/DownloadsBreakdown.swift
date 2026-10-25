import SwiftUI
import Charts

/// One slice of a downloads pie: a device or a region, and how many downloads came from it.
struct DownloadShare: Identifiable {
    let name: String
    let symbol: String
    let color: Color
    let downloads: Int

    var id: String { name }
}

/// Downloads as a pie, each slice in its share's colour. The legend is left to the caller.
struct DownloadsPie: View {

    let shares: [DownloadShare]

    var body: some View {
        Chart(shares) { share in
            SectorMark(angle: .value("Downloads", share.downloads), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(by: .value("Name", share.name))
        }
        .chartForegroundStyleScale(domain: shares.map(\.name), range: shares.map(\.color))
        .chartLegend(.hidden)
    }
}

/// A small pie over a compact legend, for the summary, which shows two side by side.
struct DownloadsPieCard: View {

    let title: LocalizedStringKey
    let shares: [DownloadShare]

    private var total: Int {
        shares.reduce(0) { $0 + $1.downloads }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            DownloadsPie(shares: shares)
                .frame(height: 110)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(shares) { share in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle()
                            .fill(share.color)
                            .frame(width: 8, height: 8)
                        Text(share.name)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        Text(Double(share.downloads) / Double(max(total, 1)), format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

    var symbol: String {
        switch self {
        case .unitedStatesAndCanada, .latinAmerica: "globe.americas"
        case .europe, .africaMiddleEastAndIndia: "globe.europe.africa"
        case .asiaPacific: "globe.asia.australia"
        case .unknown: "questionmark"
        }
    }

    var color: Color {
        switch self {
        case .unitedStatesAndCanada: .blue
        case .europe: .indigo
        case .asiaPacific: .orange
        case .latinAmerica: .green
        case .africaMiddleEastAndIndia: .pink
        case .unknown: .gray
        }
    }
}

extension ACDevice {
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
    /// Last 30 days' downloads by device, most first, with the report's device names folded into
    /// the ones App Sales knows. Every app's when `filteredApps` is empty.
    func downloadsByDevice(filteredApps: [ACApp] = []) -> [DownloadShare] {
        let byDevice = Dictionary(getDevices(.downloads, lastNDays: 30, filteredApps: filteredApps).map { (ACDevice($0.0), Int($0.1)) }, uniquingKeysWith: +)
        return byDevice
            .filter { $0.value > 0 }
            .map { DownloadShare(name: $0.key.name, symbol: $0.key.symbol, color: $0.key.color, downloads: $0.value) }
            .sorted { $0.downloads > $1.downloads }
    }

    /// Last 30 days' downloads by App Store region, most first.
    func downloadsByRegion(filteredApps: [ACApp] = []) -> [DownloadShare] {
        let startDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -30, to: .now) ?? .now
        let byRegion = Dictionary(getEntries(for: .downloads, startDate: startDate, filteredApps: filteredApps).map { (SalesRegion(countryCode: $0.countryCode), $0.units) }, uniquingKeysWith: +)
        return byRegion
            .filter { $0.value > 0 }
            .map { DownloadShare(name: $0.key.name, symbol: $0.key.symbol, color: $0.key.color, downloads: $0.value) }
            .sorted { $0.downloads > $1.downloads }
    }
}
