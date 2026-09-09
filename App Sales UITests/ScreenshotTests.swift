import XCTest

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

        // The 30-day proceeds total, the first thing the seeded account puts on screen. Waiting on
        // it means a capture cannot beat the summary and its chart onto the screen.
        let proceeds = element("Summary.Proceeds")
        guard proceeds.waitForExistence(timeout: 30) else {
            attach(XCTAttachment(string: app.debugDescription), named: "element-tree")
            return XCTFail("seeded content never appeared")
        }
        settle()
        capture("01-home")
    }

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
