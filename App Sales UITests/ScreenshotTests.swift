import XCTest
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Drives the app to the screen that becomes an App Store screenshot and attaches it to the result
/// bundle, where the shared `screenshots` runner collects it.
///
/// One shot per platform, and it is the last slot on the listing: the ones before it are hand-made
/// marketing images, kept in "Raw Assets/Screenshots" under the low numbers the runner never writes
/// (see IPHONE_MANUAL_SHOTS and friends in .screenshots.conf). This one carries the real thing —
/// the summary and its chart over the seeded account — so the listing ends on the actual app.
@MainActor
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    func testCaptureAppStoreScreenshots() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-screenshotMode"]
        app.launch()

        #if os(macOS)
        openWindowIfNeeded()
        #endif

        checkSeedIsThrowaway()

        // The 30-day proceeds total, the first thing the seeded account puts on screen. Waiting on
        // it means a capture cannot beat the summary and its chart onto the screen.
        let proceeds = element("Summary.Proceeds")
        guard waitFor(proceeds, "the seeded proceeds summary") else { return }
        settle()
        capture("01-home")
    }

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
    /// own New Window.
    ///
    /// Whether a launch gets away without this depends on who started the run: LaunchServices
    /// activates a launched app only while the process that launched it is frontmost, so the same
    /// walk comes up with a window when it is run by hand from a frontmost Terminal and with
    /// nothing but a menu bar when an agent runs it in the background.
    ///
    /// Waits first rather than counting windows straight after `launch()`, which returns on idle
    /// and can beat the window into the accessibility tree — ⌘N would then open a second, empty one
    /// and the walk would photograph that.
    private func openWindowIfNeeded() {
        if app.windows.firstMatch.waitForExistence(timeout: 10) { return }
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15),
                      "the app launched with no window and ⌘N opened none")
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
        attach(XCTAttachment(screenshot: XCUIScreen.main.screenshot()), named: name)
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
