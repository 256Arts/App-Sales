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

        save(signIn)
    }

    func disconnect(_ assistant: AIAssistant) {
        inFlight[assistant]?.cancel()
        inFlight[assistant] = nil
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

    /// This assistant's limits — from the shared cache while that reading is still fresh, from the
    /// assistant otherwise.
    ///
    /// `allowingCached` is what a deliberate refresh sets to `false`. Everything that draws on its
    /// own schedule — a widget timeline, the menu bar extra opening, the home screen appearing —
    /// leaves it alone, so the four of them together still only ask as often as one of them would.
    func usage(for assistant: AIAssistant, allowingCached: Bool = true) async throws -> AIUsage {
        if allowingCached, let cached = AIUsageCache.usage(for: assistant, newerThan: AIUsageCache.freshness) {
            return cached
        }
        if let existing = inFlight[assistant] {
            return try await existing.value
        }

        let task = Task { try await fetchUsage(for: assistant) }
        inFlight[assistant] = task
        defer { inFlight[assistant] = nil }

        let usage = try await task.value
        AIUsageCache.save(usage)
        return usage
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
