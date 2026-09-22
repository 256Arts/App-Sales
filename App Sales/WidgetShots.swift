import SwiftUI

/// Transparent PNGs of every widget and the menu bar extra, for composing marketing shots by hand.
///
/// Switched on by `-widgetShots` alongside `-screenshotMode`.
/// Neither surface can be photographed by a UI test — widgets live on a home screen the test does
/// not own, and the menu bar is outside any window — so the app draws the same views itself and
/// exits. The iPhone draws the widgets, since the Lock Screen families exist only there; the Mac
/// draws the menu bar. Each image leaves on stdout as `WIDGETSHOT<tab>name<tab>scale<tab>base64` —
/// the contract of the shared `widget-screenshots` in Repos/Scripts, which lays them out on
/// wallpapers for the listing.
///
/// None of this is the system's own rendering: corner radius, margins, and the dark tile colour are
/// estimates, and the Lock Screen's vibrant monochrome is approximated as plain white.
enum WidgetShots {

    static func renderIfRequested() {
        guard ScreenshotMode.isActive, ProcessInfo.processInfo.arguments.contains("-widgetShots") else { return }
        MainActor.assumeIsolated {
            #if os(iOS)
            renderWidgets()
            #elseif os(macOS)
            renderMenuBar()
            #endif
        }
        exit(0)
    }

    private static func emit(_ png: Data?, _ path: String, scale: Double) {
        guard let png else { return print("WIDGETSHOT-FAILED\t\(path)") }
        print("WIDGETSHOT\t\(path)\t\(scale)\t\(png.base64EncodedString())")
    }

    #if os(iOS)

    // MARK: - Widgets

    private static let looks: [(name: String, scheme: ColorScheme, tile: Color)] = [
        ("Light", .light, .white),
        ("Dark", .dark, Color(red: 0.11, green: 0.11, blue: 0.118)),
    ]

    /// iPhone 6.9" widget sizes.
    private static let small = CGSize(width: 170, height: 170)
    private static let medium = CGSize(width: 364, height: 170)
    private static let large = CGSize(width: 364, height: 382)

    private static let circular = CGSize(width: 76, height: 76)
    private static let rectangular = CGSize(width: 172, height: 76)
    private static let inline = CGSize(width: 234, height: 26)

    @MainActor
    private static func renderWidgets() {
        seedDemoIcons()
        let summary = ACData.example.getPerformanceSummary()
        let usage = AIUsageWidgetView(entry: .placeholder)

        for look in looks {
            func home(_ content: some View, _ size: CGSize, _ name: String, fill: Bool = false) {
                save(tile(content, size, look.scheme, look.tile, fill: fill), "Home Screen/\(name) \(look.name)")
            }
            home(SummarySmall(data: summary, advanced: true), small, "Sales Small")
            home(SummarySmall(data: summary, advanced: false), small, "Sales Small Simple")
            home(SummaryWithChart(data: summary, advanced: true), medium, "Sales Medium")
            home(SummaryWithChart(data: summary, advanced: false), medium, "Sales Medium Simple")
            home(SummaryWithChart(data: summary, advanced: true), large, "Sales Large")
            // The AI usage widget draws on `.fill.tertiary` over the system's tile.
            home(usage.system(showingAll: false), small, "AI Usage Small", fill: true)
            home(usage.system(showingAll: true), medium, "AI Usage Medium", fill: true)
        }

        let inlineFont = Font.system(size: 17, weight: .semibold)
        save(lock(CircularAccessory(summary: summary), circular, plate: true), "Lock Screen/Sales Circular")
        save(lock(RectangularAccessory(summary: summary), rectangular), "Lock Screen/Sales Rectangular")
        save(lock(InlineAccessory(summary: summary).font(inlineFont), inline), "Lock Screen/Sales Inline")
        save(lock(usage.circular, circular, plate: true), "Lock Screen/AI Usage Circular")
        save(lock(usage.rectangular, rectangular), "Lock Screen/AI Usage Rectangular")
        save(lock(usage.inline.font(inlineFont), inline), "Lock Screen/AI Usage Inline")
    }

    /// The widgets read app icons from the App Group, where a real fetch would have cached them.
    private static func seedDemoIcons() {
        for app in [ACApp.demo1, .demo2, .demo3, .demo4] {
            guard let url = app.cachedIconURL, let data = try? Data(contentsOf: app.iconURL512) else { continue }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }

    private static func tile(_ content: some View, _ size: CGSize, _ scheme: ColorScheme, _ color: Color, fill: Bool) -> some View {
        content
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background { if fill { Rectangle().fill(.fill.tertiary) } }
            .background(color)
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
            .environment(\.colorScheme, scheme)
    }

    /// White on transparent, the round families on their translucent backing plate.
    private static func lock(_ content: some View, _ size: CGSize, plate: Bool = false) -> some View {
        ZStack {
            if plate { Circle().fill(.white.opacity(0.2)) }
            Color.white.mask {
                content
                    .frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, .dark)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @MainActor
    private static func save(_ view: some View, _ path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.isOpaque = false
        emit(renderer.uiImage?.pngData(), path, scale: renderer.scale)
    }

    #elseif os(macOS)

    // MARK: - Menu bar

    @MainActor
    private static func renderMenuBar() {
        // The menu bar reads its options straight from the App Group, so draw them at their
        // defaults and put the reader's back afterwards.
        let defaults = UserDefaults.shared
        let keys = [UserDefaults.Key.aiUsageMetric, UserDefaults.Key.aiUsageTimeStyle, UserDefaults.Key.aiUsageGoal, UserDefaults.Key.aiUsageMenuBarStyle, UserDefaults.Key.aiUsageHidesUnreachable]
        let saved = keys.map { defaults?.object(forKey: $0) }
        keys.forEach { defaults?.removeObject(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults?.set(value, forKey: key) } }

        for (look, appearanceName) in [("Light", NSAppearance.Name.aqua), ("Dark", .darkAqua)] {
            let appearance = NSAppearance(named: appearanceName)
            // The window's content alone, to lay over glass of your own, and on a plain panel.
            for panel in [false, true] {
                let (png, scale) = snapshot(window(panel: panel), appearance: appearance)
                emit(png, "Menu Bar/Menu Bar Window \(panel ? "Panel " : "")\(look)", scale: scale)
            }

            // The extra open: its item, highlighted in a menu bar over the wallpaper, with the
            // panel hanging below it where the screen's right edge holds it.
            let extra = VStack(alignment: .trailing, spacing: 5) {
                AIUsageMenuBarGlyph(usage: AIUsage.examples.first, display: .current, style: .ring)
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, .dark)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(.white.opacity(0.25), in: .capsule)
                    .padding(.trailing, 16)
                window(panel: true)
            }
            let (png, scale) = snapshot(extra, appearance: appearance)
            emit(png, "Menu Bar/Menu Bar Extra \(look)", scale: scale)

            for style in AIUsageMenuBarStyle.allCases {
                let glyph = AIUsageMenuBarGlyph(usage: AIUsage.examples.first, display: .current, style: style)
                    .foregroundStyle(look == "Dark" ? Color.white : Color.black)
                    .padding(.horizontal, 6)
                    .frame(height: 24)
                    .environment(\.colorScheme, look == "Dark" ? .dark : .light)
                let renderer = ImageRenderer(content: glyph)
                renderer.scale = 2
                let png = renderer.nsImage?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
                emit(png, "Menu Bar/Menu Bar Item \(style.rawValue.capitalized) \(look)", scale: renderer.scale)
            }
        }
    }

    private static func window(panel: Bool) -> some View {
        AIUsageMenuBar()
            .background {
                if panel {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .strokeBorder(Color.primary.opacity(0.1))
                }
            }
    }

    /// `ImageRenderer` cannot draw the window's AppKit-backed controls, so this hosts it in a real,
    /// never-shown window and caches its display instead.
    @MainActor
    private static func snapshot(_ view: some View, appearance: NSAppearance?) -> (png: Data?, scale: Double) {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        RunLoop.main.run(until: .now.addingTimeInterval(1))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return (nil, 1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        return (rep.representation(using: .png, properties: [:]), Double(rep.pixelsWide) / host.bounds.width)
    }

    #endif
}
