import XCTest
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Walks the app through the screens that become App Store screenshots and attaches each one to the
/// result bundle, where the shared `screenshots` runner collects them.
///
/// The listing opens on hand-made widget shots, kept in "Raw Assets/Screenshots" under the low
/// numbers the runner never writes (see IPHONE_MANUAL_SHOTS and friends in .screenshots.conf); the
/// runner files these after them, in capture order: the Summary, then — on the iPhone, where it is
/// one step back — the app list, then the best seller's own page.
@MainActor
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    /// Whether the walk turned the device on its side, which the capture has to undo.
    ///
    /// Tracked here rather than read back from `XCUIDevice.shared.orientation`, which a simulator
    /// answers as portrait however the UI is laid out.
    private var isLandscape = false

    /// The seeded best seller, whose page is photographed.
    private static let featuredApp = "Forest Explorer"

    func testCaptureAppStoreScreenshots() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-screenshotMode"]
        app.launch()

        #if os(macOS)
        openWindowIfNeeded()
        #elseif os(iOS)
        turnToRequestedOrientation()
        #endif

        checkSeedIsThrowaway()

        // The 30-day proceeds total, the first thing the seeded account puts on screen. Waiting on
        // it means a capture cannot beat the summary and its chart onto the screen.
        guard waitFor(element("Summary.Proceeds"), "the seeded proceeds summary") else { return }
        settle()
        capture("01-home")

        // The watch has no app list or app pages, only the summary.
        #if !os(watchOS)
        let row = element("AppRow.\(Self.featuredApp)")
        revealSidebar(showing: row)
        guard waitFor(row, "the \(Self.featuredApp) row in the app list") else { return }
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            settle()
            capture("02-apps")
        }
        #endif

        #if os(macOS)
        row.click()
        #else
        row.tap()
        #endif
        guard waitFor(element("AppDetail.Name"), "\(Self.featuredApp)'s page") else { return }
        settle()
        capture("03-app")
        #endif
    }

    #if os(iOS)
    /// The app list is one step back from the Summary on an iPhone; the iPad (in landscape), Mac, and
    /// Vision show it all along, but the toggle is still tried in case the sidebar starts folded.
    private func revealSidebar(showing row: XCUIElement) {
        if row.waitForExistence(timeout: 2), row.isHittable { return }
        let toggle = app.buttons["Show Sidebar"]
        if toggle.exists {
            toggle.tap()
        } else {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }
    #elseif !os(watchOS)
    private func revealSidebar(showing row: XCUIElement) {}
    #endif

    // MARK: - The seed

    /// What the app said it prepared, read out of the accessibility tree.
    ///
    /// The app hangs `ScreenshotMode.status` on its root view (`.screenshotModeStatus()`). A walk
    /// that cannot find it is running against a build that has not adopted that modifier, which is
    /// worth saying plainly rather than reporting as an empty seed.
    private var seedStatus: String {
        let label = app.descendants(matching: .any)["ScreenshotMode.Status"]
        guard label.waitForExistence(timeout: 30) else {
            return "no ScreenshotMode.Status element — add .screenshotModeStatus() to the app's root view"
        }
        // A SwiftUI `Text` reaches XCUITest as the element's *value* on macOS and as its *label* on
        // iOS, so take whichever is filled in rather than betting on one.
        if let value = label.value as? String, !value.isEmpty { return value }
        return label.label
    }

    /// Stops the walk when the app did not seed its throwaway accounts.
    ///
    /// `ScreenshotMode.prepareLaunch` reports what it prepared, or nothing if a screenshot run never
    /// activated. The walk that followed would then photograph an empty app and fail on a missing
    /// row, which says nothing about why. Read the reason instead, before the first shot.
    private func checkSeedIsThrowaway() {
        let status = seedStatus
        print("SCREENSHOT MODE: \(status)")
        guard status.hasPrefix("ready") else {
            attach(XCTAttachment(string: app.debugDescription), named: "element-tree")
            return XCTFail("the app did not seed a throwaway store, so there is nothing to photograph — \(status)")
        }
    }

    private static var platform: String {
        #if os(macOS)
        "macOS"
        #elseif os(watchOS)
        "watchOS"
        #elseif targetEnvironment(macCatalyst)
        "Mac Catalyst"
        #elseif os(visionOS)
        "visionOS"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #endif
    }

    /// Which simulator this was, for a failure read days after the run's own log is gone.
    private static var device: String {
        ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "this machine"
    }

    /// Waits for `element`, and on a miss names the platform, the device, what it was waiting for,
    /// and what the app reported about its own seed — so a failure explains itself instead of just
    /// saying content never appeared.
    private func waitFor(_ element: XCUIElement, _ description: String, timeout: TimeInterval = 30) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            attach(XCTAttachment(string: app.debugDescription), named: "element-tree")
            XCTFail("""
                never found \(description) in \(Int(timeout))s on \(Self.platform), \(Self.device).
                The app reported: \(seedStatus)
                The screen at the time is attached as element-tree.
                """)
            return false
        }
        return true
    }

    #if os(macOS)
    /// Opens a window when the launch came up without one.
    ///
    /// `XCUIApplication.launch()` launches a Mac app in the *background*, and AppKit gives a
    /// background launch no window — it holds it until the user arrives. The app comes up as a menu
    /// bar and nothing else, every lookup in the walk comes back empty, and the run dies on the
    /// first wait with the seed sitting in a store no window is showing. `activate()` is not what
    /// AppKit waits for: only a reopen, the event a Dock icon click sends, builds the window, and a
    /// test runner has no way to send one — so the walk asks for the window itself, with the app's
    /// Window menu item for its one window.
    ///
    /// Whether a launch gets away without this depends on who started the run: LaunchServices
    /// activates a launched app only while the process that launched it is frontmost, so the same
    /// walk comes up with a window when it is run by hand from a frontmost Terminal and with
    /// nothing but a menu bar when an agent runs it in the background.
    ///
    /// Waits first rather than counting windows straight after `launch()`, which returns on idle
    /// and can beat the window into the accessibility tree. The main window is a single `Window`
    /// scene, so asking for it again only brings it forward — it can never open a second.
    private func openWindowIfNeeded() {
        if app.windows.firstMatch.waitForExistence(timeout: 10) { return }
        app.menuBarItems["Window"].click()
        app.menuItems["App Sales"].click()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15),
                      "the app launched with no window and the Window menu opened none")
    }
    #endif

    // MARK: - Driving

    /// Matches by accessibility identifier, label, *or* value, across the element types a control
    /// surfaces as: a toolbar item is a button carrying its label, while a SwiftUI `Text` is static
    /// text carrying its string as the *value* and no label at all.
    ///
    /// Resolved with `element(boundBy: 0)` rather than `firstMatch`, which can report
    /// `exists == false` for a query that plainly matches.
    private func element(_ name: String) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier == %@ OR label == %@ OR value == %@", name, name, name)
        for query in [app.buttons, app.staticTexts, app.cells] {
            let matches = query.matching(predicate)
            if matches.count > 0 { return matches.element(boundBy: 0) }
        }
        // Nothing matched yet — the screen may not be up. Hand back the query the caller waits on.
        return app.staticTexts.matching(predicate).element(boundBy: 0)
    }

    #if os(iOS)
    /// Turns the device the way the runner asked (`IPAD_ORIENTATION`, landscape by default on iPad).
    ///
    /// After `launch()`, not before: a rotation set before the app is up is silently dropped, and
    /// the set comes back portrait. The runner checks every shot's shape, so that fails the run.
    private func turnToRequestedOrientation() {
        guard ProcessInfo.processInfo.environment["SCREENSHOT_ORIENTATION"] == "landscape" else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        isLandscape = true
        settle()
    }
    #endif

    /// Animations and async content have no element to wait on, so the shots pause instead.
    private func settle(seconds: TimeInterval = 2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // MARK: - Capturing

    private func capture(_ name: String) {
        // Every capture below photographs the whole screen, or the frontmost window — never this
        // app in particular. So an app that has lost the foreground yields another app's UI, filed
        // under this app's name, at the right size, with nothing to notice. The shared runner holds
        // a machine-wide lock so that cannot happen; this is the check that it held.
        XCTAssertEqual(app.state, .runningForeground,
                       "\(name): the app under test was not frontmost — another app has this device")
        #if os(macOS) || os(visionOS)
        captureExternally(named: name)
        #else
        // The simulator's screen already *is* the store's canvas, at the exact required pixel size.
        attach(upright(XCUIScreen.main.screenshot()), named: name)
        #endif
    }

    /// The screenshot, turned the way the device is being held.
    ///
    /// `XCUIScreen.main.screenshot()` photographs the *physical* screen: a rotated device comes back
    /// as a portrait buffer carrying its quarter turn as metadata, which `XCTAttachment(screenshot:)`
    /// writes out content-on-its-side. Redrawing bakes the metadata into the pixels — `UIImage.size`
    /// is already the turned size and `draw(at:)` honours the orientation, so no manual rotation.
    private func upright(_ screenshot: XCUIScreenshot) -> XCTAttachment {
        #if os(iOS)
        guard isLandscape else { return XCTAttachment(screenshot: screenshot) }
        let image = screenshot.image
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale   // keep the pixel count the store checks against
        format.opaque = true
        return XCTAttachment(image: UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        })
        #else
        XCTAttachment(screenshot: screenshot)
        #endif
    }

    private func attach(_ attachment: XCTAttachment, named name: String) {
        attachment.name = name
        attachment.lifetime = .keepAlways   // attachments on a passing test are discarded otherwise
        add(attachment)
    }

    #if os(macOS) || os(visionOS)

    /// Asks the shell running the tests to photograph the app, and waits for it.
    ///
    /// On the Mac the good capture is `screencapture -l`, which reads the window's own buffer:
    /// correctly masked to the rounded corners, with real alpha and the system's own shadow.
    /// (`XCUIElement.screenshot()` crops the *screen* to the window's frame, so it loses the shadow —
    /// drawn outside that frame — and leaves desktop inside the corners.) But `screencapture` needs
    /// Screen Recording, which the test runner has no grant for and the terminal running the script
    /// does. So the test drives the UI and the script takes the picture.
    ///
    /// visionOS goes the same way for a different reason: it has no screen for
    /// `XCUIScreen.main.screenshot()` to return, so the runner shoots the simulator from outside
    /// with `simctl io screenshot` and gets the window and its backdrop at the store's own size.
    ///
    /// They meet in a plain directory under /tmp, which works only because the runner is deliberately
    /// unsandboxed (UITests.entitlements): a sandboxed runner cannot write /tmp, and its own container
    /// is unreadable to the script, so the two would have nowhere to meet.
    private static let handshakeDirectory = URL(fileURLWithPath: "/tmp/app-store-screenshots")

    private func captureExternally(named name: String) {
        let files = FileManager.default
        let handshake = Self.handshakeDirectory
        let done = handshake.appendingPathComponent("done-\(name)")
        try? files.removeItem(at: done)

        let request = handshake.appendingPathComponent("request-\(name)")
        guard files.createFile(atPath: request.path, contents: nil) else {
            return XCTFail("could not write a capture request to \(request.path)")
        }

        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if files.fileExists(atPath: done.path) { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("timed out waiting for the script to capture \(name) — is the runner watching \(handshake.path)?")
    }

    #endif
}
