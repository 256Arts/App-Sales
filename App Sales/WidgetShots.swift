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
/// The one exception is Liquid Glass, which only the window server draws. Under `-glassTile` the Mac
/// takes a finished shot on stdin, lays that tile on real glass over it in an on-screen window,
/// captures the window, and prints the whole shot back — see `renderGlass()`.
///
/// Otherwise none of this is the system's own rendering: corner radius, margins, and the dark tile colour are
/// estimates, and the Lock Screen's vibrant monochrome is approximated as plain white.
enum WidgetShots {

    static func renderIfRequested() {
        guard ScreenshotMode.isActive, ProcessInfo.processInfo.arguments.contains("-widgetShots") else { return }
        MainActor.assumeIsolated {
            #if os(iOS)
            renderWidgets()
            #elseif os(macOS)
            withDefaultOptions {
                if ProcessInfo.processInfo.arguments.contains("-glassTile") { renderGlass() } else { renderMenuBar() }
            }
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

    /// The menu bar reads its options straight from the App Group, so draw them at their defaults and
    /// put the reader's back afterwards.
    private static func withDefaultOptions(_ body: () -> Void) {
        let defaults = UserDefaults.shared
        let keys = [UserDefaults.Key.aiUsageMetric, UserDefaults.Key.aiUsageTimeStyle, UserDefaults.Key.aiUsageGoal, UserDefaults.Key.aiUsageMenuBarStyle, UserDefaults.Key.aiUsageHidesUnreachable]
        let saved = keys.map { defaults?.object(forKey: $0) }
        keys.forEach { defaults?.removeObject(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults?.set(value, forKey: key) } }
        body()
    }

    @MainActor
    private static func renderMenuBar() {
        // Only its size and place in the layout: the composer leaves its spot bare for
        // `renderGlass()` to fill.
        let (png, scale) = snapshot(menuBarExtra(onGlass: false), appearance: NSAppearance(named: .aqua))
        emit(png, "Menu Bar/Menu Bar Extra", scale: scale)

        for (look, appearanceName) in [("Light", NSAppearance.Name.aqua), ("Dark", .darkAqua)] {
            let appearance = NSAppearance(named: appearanceName)
            // The window's content alone, to lay over glass of your own, and on a plain panel.
            for panel in [false, true] {
                let (png, scale) = snapshot(window(panel: panel), appearance: appearance)
                emit(png, "Menu Bar/Menu Bar Window \(panel ? "Panel " : "")\(look)", scale: scale)
            }

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

    /// The extra open: its item highlighted in the menu bar, with the panel hanging below it where the
    /// screen's right edge holds it. White on clear glass, whatever the appearance — only the glass
    /// itself stays light, which keeps it from tinting the wallpaper either way.
    @ViewBuilder
    private static func menuBarExtra(onGlass: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            AIUsageMenuBarGlyph(usage: AIUsage.examples.first, display: .current, style: .ring)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(.white.opacity(0.25), in: .capsule)
                .padding(.trailing, 16)
            if onGlass {
                AIUsageMenuBar()
                    .environment(\.colorScheme, .dark)
                    .glassEffect(.clear, in: .rect(cornerRadius: 16))
                    .environment(\.colorScheme, .light)
            } else {
                AIUsageMenuBar()
            }
        }
        .environment(\.colorScheme, .dark)
    }

    /// Lays `-glassTile` on real glass over the shot on stdin, where `-glassFrame` (canvas pixels)
    /// puts it at `-glassScale` pixels per point, and prints the whole shot back.
    ///
    /// The glass has to sit in a window over the real pixels to bend them, so the window holds the
    /// shot's pixels around that frame with the tile on top, and is captured by the window server.
    @MainActor
    private static func renderGlass() {
        func argument(_ flag: String) -> String {
            let arguments = ProcessInfo.processInfo.arguments
            return arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? ""
        }
        let name = argument("-glassTile")
        let frame = argument("-glassFrame").split(separator: ",").compactMap { Double($0) }
        let scale = Double(argument("-glassScale")) ?? 0
        let stdin = FileHandle.standardInput.readDataToEndOfFile()
        guard name.hasSuffix("Menu Bar Extra"), frame.count == 4, scale > 0,
              let source = CGImageSourceCreateWithData(stdin as CFData, nil),
              let canvas = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return emit(nil, name, scale: 1) }

        // Some of the shot beyond the tile, so the glass's edges bend real pixels too.
        let tile = CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3])
        let area = tile.insetBy(dx: -48, dy: -48).integral.intersection(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        guard let backdrop = canvas.cropping(to: area) else { return emit(nil, name, scale: 1) }

        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.level = .floating
        let pixels = window.backingScaleFactor
        let content = ZStack(alignment: .topLeading) {
            Image(decorative: backdrop, scale: pixels)
            menuBarExtra(onGlass: true)
                .fixedSize()
                .scaleEffect(scale / pixels, anchor: .topLeading)
                .offset(x: (tile.minX - area.minX) / pixels, y: (tile.minY - area.minY) / pixels)
        }
        window.contentView = NSHostingView(rootView: content)
        window.setFrame(CGRect(origin: NSScreen.main?.visibleFrame.origin ?? .zero, size: CGSize(width: area.width / pixels, height: area.height / pixels)), display: true)
        window.orderFrontRegardless()
        RunLoop.main.run(until: .now.addingTimeInterval(1.5))
        defer { window.orderOut(nil) }
        guard let glass = captureWindow(window.windowNumber) else { return emit(nil, name, scale: 1) }

        guard let context = CGContext(data: nil, width: canvas.width, height: canvas.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return emit(nil, name, scale: 1) }
        let height = Double(canvas.height)
        context.interpolationQuality = .high
        context.draw(canvas, in: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        context.draw(glass, in: CGRect(x: area.minX, y: height - area.maxY, width: area.width, height: area.height))
        emit(context.makeImage().flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }, name, scale: 1)
    }

    /// `CGWindowListCreateImage` is marked unavailable in the SDK, but it still captures the app's own
    /// windows — glass and all — with no Screen Recording permission, which ScreenCaptureKit needs.
    /// Looked up at runtime so a macOS that drops it fails the shot rather than the build.
    private static func captureWindow(_ number: Int) -> CGImage? {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return nil }
        let createImage = unsafeBitCast(symbol, to: CreateImage.self)
        // Including just this window; ignoring its framing, at its best resolution.
        return createImage(.null, 1 << 3, UInt32(number), 1 << 0 | 1 << 3)?.takeRetainedValue()
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
