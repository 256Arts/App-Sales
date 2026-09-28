import AppTrackingTransparency
#if canImport(AdmobSwiftUI)
import AdmobSwiftUI
#endif

/// Decides when ads and App Store review requests appear, so both ramp up with the same engagement.
final class ExperienceManager {

    static let shared = ExperienceManager()

    /// The launches at which to ask for an App Store review.
    let launchCountsToAskForReview = [5, 20, 50, 100]

    var trackingAuthorizationStatus: ATTrackingManager.AuthorizationStatus = .notDetermined

    #if canImport(AdmobSwiftUI)
    private var adsStarted = false

    /// Asks for tracking consent, then starts the Google Mobile Ads SDK — never the reverse, as the
    /// SDK collects device data the moment it starts. Does nothing until the reader qualifies for
    /// ads, so the prompt arrives alongside the first ad rather than on first launch. Call once the
    /// scene is active: the system silently skips the prompt otherwise, so an undetermined result
    /// waits for the next activation.
    @MainActor
    func requestTrackingThenStartAds() async {
        guard !adsStarted, qualifiesForAds, !ScreenshotMode.isActive else { return }
        trackingAuthorizationStatus = await ATTrackingManager.requestTrackingAuthorization()
        guard trackingAuthorizationStatus != .notDetermined else { return }
        adsStarted = true
        AdmobSwiftUI.initialize()
    }

    /// Only once the reader is past the first review request, so a new reader gets a clean app.
    private var qualifiesForAds: Bool {
        #if DEBUG
        true
        #else
        UserDefaults.standard.integer(forKey: UserDefaults.Key.appLaunchCount) > (launchCountsToAskForReview.first ?? 0)
        #endif
    }
    #endif

    var shouldShowAds: Bool {
        #if canImport(AdmobSwiftUI)
        // Loading an ad would start the SDK itself, ahead of the tracking prompt
        guard adsStarted else { return false }
        #if DEBUG
        // A debug device has to expose its tracking ID for Google to serve it test ads
        return trackingAuthorizationStatus == .authorized
        #else
        return true
        #endif
        #else
        return false
        #endif
    }

}
