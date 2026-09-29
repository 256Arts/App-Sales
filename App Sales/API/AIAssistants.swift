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

    private(set) var signIns: [AIUsageSignIn] = []

    /// An assistant whose sign-in the app has been asked to show — by a row or the menu bar extra
    /// finding it refused — so the one sheet can be presented from wherever the window is.
    var signingIn: AIAssistant?

    /// Connected assistants, always in the same order, so the section does not reshuffle itself.
    var connected: [AIAssistant] {
        AIAssistant.allCases.filter { signIn(for: $0) != nil }
    }

    private static let keychain = Keychain(service: "com.jaydenirwin.appsales")
        .synchronizable(true)
    private static let keychainKey = "ai-assistants"

    private init() {
        signIns = Self.stored() ?? []
    }

    /// What the Keychain holds now; `nil` when it could not be read, which is not the same as empty.
    private static func stored() -> [AIUsageSignIn]? {
        // A screenshot run stays off the real Keychain, as `AccountManager` does.
        guard !ScreenshotMode.isActive else { return [] }

        do {
            guard let data = try keychain.getData(keychainKey) else { return [] }

            return try JSONDecoder().decode([AIUsageSignIn].self, from: data)
        } catch {
            return nil
        }
    }

    /// Picks up what other processes and devices have written since this one last looked.
    ///
    /// Every refresh rotates the refresh token, and the widget extension, the watch, and the other
    /// devices all refresh too. A copy held from launch goes stale the first time one of them does,
    /// and refreshing with it spends a token that is already spent — which the assistant takes as a
    /// stolen one, and answers by revoking the sign-in everywhere.
    private func reload() {
        guard let stored = Self.stored(), stored != signIns else { return }

        signIns = stored
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
        reload()
        signIns.removeAll { $0.assistant == assistant }
        persist()
        AIUsageCache.clear(assistant)
    }

    /// Read, change, write — so saving one assistant never writes back a stale copy of the other.
    private func save(_ signIn: AIUsageSignIn) {
        reload()
        signIns.removeAll { $0.assistant == signIn.assistant }
        signIns.append(signIn)
        persist()
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
    private(set) var failures: [AIAssistant: any Error] = [:]

    /// Whether this assistant refused its sign-in, which only signing in again will fix.
    func needsSignIn(_ assistant: AIAssistant) -> Bool {
        guard case .signInExpired = failures[assistant] as? AIUsageError else { return false }

        return true
    }

    /// This assistant's limits — from the shared cache while that reading is younger than `maxAge`,
    /// or while a window it shows has run out and not yet reset, from the assistant otherwise.
    ///
    /// A deliberate refresh passes `0`, and always asks. Everything that draws on its own schedule —
    /// a widget timeline, the menu bar extra opening, the home screen appearing — leaves it alone, so
    /// the four of them together still only ask as often as one of them would.
    func usage(for assistant: AIAssistant, maxAge: TimeInterval = AIUsageCache.freshness) async throws -> AIUsage {
        reload()
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
            failures[assistant] = error
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
        reload()
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

        if signIn.expiresSoon {
            signIn = try await refreshed(signIn)
        }
        do {
            return try await AIUsageAPI.usage(signIn)
        } catch AIUsageError.signInExpired {
            // Refused before it said it would expire: refreshed by another process, or revoked.
            signIn = try await refreshed(signIn)
            return try await AIUsageAPI.usage(signIn)
        }
    }

    /// Refreshes a sign-in and saves the result, so every device the Keychain reaches gets the new
    /// token rather than each refreshing — and rotating — in turn.
    ///
    /// Held under a lock in the App Group, since the app and its widget extension are separate
    /// processes that can both find the same token expired in the same minute. Whoever gets
    /// the lock second finds the first one's token in the Keychain and uses that instead.
    private func refreshed(_ spent: AIUsageSignIn) async throws -> AIUsageSignIn {
        let lock = try await AIUsageRefreshLock.acquire(for: spent.assistant)
        defer { lock.release() }

        reload()
        guard let current = signIn(for: spent.assistant) else { throw AIUsageError.notSignedIn }

        if current != spent, !current.expiresSoon {
            return current
        }
        // Refused here can still mean another device refreshed first and its token has not synced
        // yet — nothing is saved, so the next fetch reads the Keychain again and picks it up.
        let refreshed = try await AIUsageAPI.refresh(current)
        save(refreshed)
        return refreshed
    }
}

/// One refresh per assistant across every process on this device, as `flock` on a file in the App
/// Group. Polled rather than blocked on, so waiting never ties up the main thread, and released by
/// the system if the process holding it dies.
private struct AIUsageRefreshLock {

    private let descriptor: Int32

    static func acquire(for assistant: AIAssistant) async throws -> AIUsageRefreshLock {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appending(path: "ai-refresh-\(assistant.rawValue).lock") else {
            // Without the App Group there is no other process to share the token with.
            return AIUsageRefreshLock(descriptor: -1)
        }

        let descriptor = open(url.path(percentEncoded: false), O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return AIUsageRefreshLock(descriptor: -1) }

        // A refresh is one request with a 30-second timeout, so a holder is done well inside this.
        for _ in 0..<160 {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                return AIUsageRefreshLock(descriptor: descriptor)
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                close(descriptor)
                throw error
            }
        }
        close(descriptor)
        throw AIUsageError.assistant(String(localized: "\(assistant.name) could not be reached."))
    }

    func release() {
        guard descriptor >= 0 else { return }

        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
