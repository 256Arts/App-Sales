import XCTest

/// Drives the app through the screens that become App Store screenshots and attaches each one to the
/// result bundle, where the shared `screenshots` runner collects them.
///
/// One test rather than one per screen: the shots are a walk through a single launch, and splitting
/// them would pay the launch — and the reseed — every time.
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

        // The bottom of the list: Apple Intelligence's read on the numbers, and the per-app rows.
        // Framed by scrolling to the *last* app rather than to the Insights header, which would stop
        // with the section clipped against the bottom edge.
        scroll(to: element("Sunset Seeker"), description: "the bottom of the list")
        settle()
        capture("02-insights")

        // Skipped on the Mac, where `screencapture -l` photographs one window and a sheet is its
        // own — the shot would arrive without the app around it.
        #if !os(macOS)
        activate(element("Accounts"), "the Accounts button")
        settle()
        capture("03-accounts")
        #endif
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

    private func activate(_ element: XCUIElement, _ description: String) {
        guard element.waitForExistence(timeout: 15) else {
            attach(XCTAttachment(string: app.debugDescription), named: "element-tree")
            return XCTFail("never found \(description)")
        }
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    /// Scrolls the home list until `element` is inside the rectangle the shot will show.
    ///
    /// Framing is measured rather than asked for: `isHittable` is false for the static text in a
    /// `List` row on the Mac whether it is on screen or not, so it cannot answer this. A blind swipe
    /// also travels a different distance on every device, hence stepping and re-checking. The second
    /// half of the budget scrolls the other way, because a scroll wheel's sign is not worth guessing
    /// at and the wrong guess only costs the steps that walk back to where it began.
    private func scroll(to element: XCUIElement, description: String) {
        // Deliberately not waiting on the element first: a `List` on iOS is lazy, so a row below the
        // fold does not exist until something scrolls it into being.
        let steps = 8
        for step in 0 ..< (steps * 2) {
            if element.exists && visibleFrame.contains(element.frame) { return }
            scrollList(down: step < steps)
        }
        attach(XCTAttachment(string: app.debugDescription), named: "element-tree")
        XCTFail("never scrolled \(description) into view (it sits at \(element.frame), the shot shows \(visibleFrame))")
    }

    /// The rectangle a shot will actually show: the app's window on the Mac, the screen elsewhere.
    private var visibleFrame: CGRect {
        #if os(macOS)
        return app.windows.element(boundBy: 0).frame
        #else
        return app.frame
        #endif
    }

    private func scrollList(down: Bool) {
        #if os(macOS)
        // The scroll view itself, not the window: a wheel event delivered to the window is ignored.
        // `scroll(to:description:)` sorts out the sign.
        let scrollView = app.scrollViews.element(boundBy: 0)
        let scrollable = scrollView.exists ? scrollView : app.windows.element(boundBy: 0)
        scrollable.scroll(byDeltaX: 0, deltaY: down ? -160 : 160)
        #else
        if down {
            app.swipeUp()
        } else {
            app.swipeDown()
        }
        #endif
    }

    /// Animations and async content have no element to wait on, so the shots pause instead.
    private func settle(seconds: TimeInterval = 2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // MARK: - Capturing

    private func capture(_ name: String) {
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
