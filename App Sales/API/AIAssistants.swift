import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
import KeychainAccess

/// The assistants the reader has connected, and what is left of their limits.
///
/// The connections are one per reader rather than one per App Store Connect account, and they live
/// in the same iCloud-synchronized Keychain as everything else here — so a sign-in taken from the
/// Mac's terminal, the only place it can be taken from, reaches the phone and the watch too.
@MainActor
@Observable
final class AIAssistants {

    static let shared = AIAssistants()

    private(set) var signIns: [AIUsageSignIn] = [] {
        didSet { persist() }
    }

    /// Connected assistants, always in the same order, so the section does not reshuffle itself.
    var connected: [AIAssistant] {
        AIAssistant.allCases.filter { signIn(for: $0) != nil }
    }

    private static let keychain = Keychain(service: "com.jaydenirwin.appsales")
        .synchronizable(true)
    private static let keychainKey = "ai-assistants"

    private init() {
        // A screenshot run stays off the real Keychain, as `AccountManager` does.
        guard !ScreenshotMode.isActive,
              let data = try? Self.keychain.getData(Self.keychainKey) else { return }

        signIns = (try? JSONDecoder().decode([AIUsageSignIn].self, from: data)) ?? []
    }

    func signIn(for assistant: AIAssistant) -> AIUsageSignIn? {
        signIns.first { $0.assistant == assistant }
    }

    /// Connects an assistant from what the reader pasted or picked.
    func connect(_ assistant: AIAssistant, with text: String) throws {
        guard let signIn = AIUsageSignIn.read(text, for: assistant) else {
            throw AIUsageError.unreadableSignIn(assistant)
        }

        connect(signIn)
    }

    /// Connects an assistant from a sign-in the app negotiated itself.
    func connect(_ signIn: AIUsageSignIn) {
        save(signIn)
        latest[signIn.assistant] = nil
        failures[signIn.assistant] = nil
        AIUsageCache.clear(signIn.assistant)
    }

    func disconnect(_ assistant: AIAssistant) {
        inFlight[assistant]?.cancel()
        inFlight[assistant] = nil
        latest[assistant] = nil
        failures[assistant] = nil
        signIns.removeAll { $0.assistant == assistant }
        AIUsageCache.clear(assistant)
    }

    private func save(_ signIn: AIUsageSignIn) {
        signIns.removeAll { $0.assistant == signIn.assistant }
        signIns.append(signIn)
    }

    private func persist() {
        guard !ScreenshotMode.isActive else { return }

        if signIns.isEmpty {
            try? Self.keychain.remove(Self.keychainKey)
        } else if let data = try? JSONEncoder().encode(signIns) {
            try? Self.keychain.set(data, key: Self.keychainKey)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: Fetching

    /// One fetch per assistant at a time. Two overlapping fetches could each refresh the same token,
    /// and a refresh token used twice gets its whole family revoked — which would sign the reader's
    /// terminal out, not just App Sales.
    private var inFlight: [AIAssistant: Task<AIUsage, Error>] = [:]

    /// The last reading this process has seen of each assistant, cached or fetched — what the home
    /// screen section draws, so the minute-by-minute refresh below reaches it without a hand-off.
    private(set) var latest: [AIAssistant: AIUsage] = [:]
    /// Why the last fetch of each assistant failed, until one works.
    private(set) var failures: [AIAssistant: String] = [:]

    /// This assistant's limits — from the shared cache while that reading is younger than `maxAge`,
    /// or while a window it shows has run out and not yet reset, from the assistant otherwise.
    ///
    /// A deliberate refresh passes `0`, and always asks. Everything that draws on its own schedule —
    /// a widget timeline, the menu bar extra opening, the home screen appearing — leaves it alone, so
    /// the four of them together still only ask as often as one of them would.
    func usage(for assistant: AIAssistant, maxAge: TimeInterval = AIUsageCache.freshness) async throws -> AIUsage {
        if maxAge > 0, let cached = AIUsageCache.usage(for: assistant),
           cached.fetched.timeIntervalSinceNow > -maxAge || cached.exhaustedUntil() != nil {
            latest[assistant] = cached
            return cached
        }
        if let existing = inFlight[assistant] {
            return try await existing.value
        }

        let task = Task { try await fetchUsage(for: assistant) }
        inFlight[assistant] = task
        defer { inFlight[assistant] = nil }

        let usage: AIUsage
        do {
            usage = try await task.value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            failures[assistant] = error.localizedDescription
            throw error
        }
        AIUsageCache.save(usage)
        latest[assistant] = usage
        failures[assistant] = nil
        return usage
    }

    /// What the app does once a minute while it is on screen — the window, or the Mac's menu bar
    /// extra — so the figures move while the work is being done: every connected assistant asked in
    /// turn, then the AI usage widget told to redraw from what came back.
    ///
    /// Half the minute as the cache age by default, so a reading another process took in the last
    /// half minute is as good as one of our own and two open surfaces do not each ask. The widget
    /// reload is free while the app is in the foreground — WidgetKit only budgets the reloads a
    /// widget asks for itself — and its timeline finds this reading in the cache rather than
    /// fetching again.
    ///
    /// Returns whether every assistant answered.
    @discardableResult
    func refreshConnected(maxAge: TimeInterval = 30) async -> Bool {
        guard !connected.isEmpty else { return true }

        var succeeded = true

        // In turn, not at once: two fetches could each refresh the same token.
        for assistant in connected {
            do {
                _ = try await usage(for: assistant, maxAge: maxAge)
            } catch {
                succeeded = false
            }
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: AIUsageCache.widgetKind)
        #endif
        return succeeded
    }

    private func fetchUsage(for assistant: AIAssistant) async throws -> AIUsage {
        guard var signIn = signIn(for: assistant) else { throw AIUsageError.notSignedIn }

        if signIn.isExpired {
            signIn = try await refreshed(signIn)
        }
        do {
            return try await AIUsageAPI.usage(signIn)
        } catch AIUsageError.signInExpired {
            // Refused before it said it would expire: rotated by the terminal, or revoked there.
            signIn = try await refreshed(signIn)
            return try await AIUsageAPI.usage(signIn)
        }
    }

    /// Refreshes a sign-in and saves the result, so every device the Keychain reaches gets the new
    /// token rather than each refreshing — and rotating — in turn.
    private func refreshed(_ signIn: AIUsageSignIn) async throws -> AIUsageSignIn {
        let refreshed = try await AIUsageAPI.refresh(signIn)
        save(refreshed)
        return refreshed
    }
}
