import SwiftUI
import UniformTypeIdentifiers
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The home screen's AI usage: how much of each connected assistant's five-hour and weekly limits
/// is gone, and when they refill.
///
/// The work that produces the sales above it is increasingly done with these, and their limits are
/// the thing that stops a day's work — so they belong on the same screen, read the same way.
struct AIUsageSection: View {

    @State private var assistants = AIAssistants.shared
    @State private var usage: [AIAssistant: AIUsage] = [:]
    @State private var errors: [AIAssistant: String] = [:]

    @AppStorage(UserDefaults.Key.aiUsageMetric, store: UserDefaults.shared) private var metric: AIUsageMetric = .used
    @AppStorage(UserDefaults.Key.aiUsageTimeStyle, store: UserDefaults.shared) private var timeStyle: AIUsageTimeStyle = .relative
    @AppStorage(UserDefaults.Key.aiUsageGoal, store: UserDefaults.shared) private var goal: AIUsageGoal = .none

    private var display: AIUsageDisplay {
        AIUsageDisplay(metric: metric, timeStyle: timeStyle, goal: goal)
    }
    private var connected: [AIAssistant] {
        ScreenshotMode.isActive ? AIUsage.examples.map(\.assistant) : assistants.connected
    }

    var body: some View {
        Section {
            if connected.isEmpty {
                Text("Connect Claude or Codex in Accounts to see how much of each one's limits you have left, beside the day's sales.")
                    .foregroundStyle(.secondary)
            }

            ForEach(connected) { assistant in
                AIUsageRow(assistant: assistant, usage: usage[assistant], error: errors[assistant], display: display)
            }
        } header: {
            HStack {
                Label("AI Usage", systemImage: "gauge.with.dots.needle.33percent")

                Spacer()

                Menu {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await load(maxAge: 0) }
                    }

                    Divider()

                    AIUsageOptions()
                } label: {
                    Label("Options", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
                .menuIndicator(.hidden)
            }
        } footer: {
            if !connected.isEmpty {
                Text("Limits refill on a rolling five-hour and seven-day window.")
            }
        }
        .task(id: connected) {
            await load()
        }
    }

    private func load(maxAge: TimeInterval = AIUsageCache.freshness) async {
        guard !ScreenshotMode.isActive else {
            usage = Dictionary(uniqueKeysWithValues: AIUsage.examples.map { ($0.assistant, $0) })
            return
        }

        // One assistant at a time. Two at once could each find their sign-in expired and each
        // refresh it, and a refresh token used twice gets its family revoked — which would sign the
        // reader's own terminal out, not just App Sales.
        for assistant in assistants.connected {
            do {
                usage[assistant] = try await assistants.usage(for: assistant, maxAge: maxAge)
                errors[assistant] = nil
            } catch {
                errors[assistant] = error.localizedDescription
            }
        }
    }
}

/// One assistant's two windows, or why they could not be read.
private struct AIUsageRow: View {

    let assistant: AIAssistant
    let usage: AIUsage?
    let error: String?
    let display: AIUsageDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(assistant.name, systemImage: assistant.systemImage)

                Spacer()

                if let plan = usage?.plan {
                    Text(plan)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let usage {
                AIUsageBar(window: .fiveHour, usage: usage, display: display)
                AIUsageBar(window: .week, usage: usage, display: display)
            } else if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The choices every surface that draws usage obeys, as menu contents — so the home screen section
/// and the Mac's menu bar extra offer exactly the same ones rather than drifting apart.
///
/// The metric and the time style live in the App Group, which is how the widgets and the watch
/// complications see them; changing either reloads the timelines, because a widget process will not
/// notice a preference it is not watching.
struct AIUsageOptions<MenuBarItems: View>: View {

    /// Choices only the menu bar extra itself offers, filed under its section beside the toggle.
    @ViewBuilder var menuBarItems: MenuBarItems

    @AppStorage(UserDefaults.Key.aiUsageMetric, store: UserDefaults.shared) private var metric: AIUsageMetric = .used
    @AppStorage(UserDefaults.Key.aiUsageTimeStyle, store: UserDefaults.shared) private var timeStyle: AIUsageTimeStyle = .relative
    @AppStorage(UserDefaults.Key.aiUsageGoal, store: UserDefaults.shared) private var goal: AIUsageGoal = .none
    #if os(macOS)
    @AppStorage(UserDefaults.Key.aiUsageMenuBarExtra, store: UserDefaults.shared) private var showsMenuBarExtra = false
    #endif

    var body: some View {
        // Bindings rather than `.onChange`: these are menu contents, so a modifier on a wrapper
        // would be applied to every child and fire the reload once per picker.
        Section("Usage") {
            Picker("Show", selection: binding($metric)) {
                ForEach(AIUsageMetric.allCases) { metric in
                    Text(metric.name)
                        .tag(metric)
                }
            }

            Picker("Reset Time", selection: binding($timeStyle)) {
                ForEach(AIUsageTimeStyle.allCases) { style in
                    Text(style.name)
                        .tag(style)
                }
            }

            Picker("Goal", selection: binding($goal)) {
                ForEach(AIUsageGoal.allCases) { goal in
                    Text(goal.name)
                        .tag(goal)
                }
            }
        }

        #if os(macOS)
        Section("Menu Bar") {
            Toggle("Show in Menu Bar", isOn: $showsMenuBarExtra)

            menuBarItems
        }
        #endif
    }

    /// Writes the choice through, then tells the widgets — a widget process is not watching these
    /// defaults, so it has no other way to hear about the change.
    private func binding<Value>(_ source: Binding<Value>) -> Binding<Value> {
        Binding {
            source.wrappedValue
        } set: { newValue in
            source.wrappedValue = newValue
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }
}

extension AIUsageOptions where MenuBarItems == EmptyView {
    init() {
        self.init { EmptyView() }
    }
}

/// Connecting an assistant: sign in to it in a browser, or — where it has no sign-in an app can
/// drive — paste what its command line tool prints, or on a Mac hand over the file it keeps.
/// Presented from Accounts, beside the App Store Connect keys.
struct AIUsageSignInSheet: View {

    let assistant: AIAssistant

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var text = ""
    @State private var error: String?
    @State private var choosingFile = false
    @State private var connecting = false
    /// The sign-in the reader is part way through, holding the secrets that finish it. Non-`nil`
    /// once the browser has been opened, which is also what brings the code field out.
    @State private var signInRequest: AIUsageAPI.SignInRequest?

    var body: some View {
        NavigationStack {
            Form {
                if let signInCommand = assistant.signInCommand {
                    Section {
                        TextField("Sign-in", text: $text, axis: .vertical)
                            .lineLimit(3...8)
                            .font(.footnote.monospaced())
                            #if canImport(UIKit)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                    } header: {
                        Text("Paste Sign-In")
                    } footer: {
                        Text("Run `\(signInCommand)` in a terminal and paste what it prints.")
                    }

                    #if os(macOS)
                    // Only for an assistant that keeps its sign-in in a file. Claude Code keeps its
                    // own in a Keychain item nothing else can open, and signs in here anyway.
                    if let credentialsFile = assistant.credentialsFile {
                        Section {
                            Button("Choose Sign-In File…", systemImage: "folder") {
                                choosingFile = true
                            }
                        } footer: {
                            Text("Reads the sign-in your terminal is already using, at ~/\(credentialsFile). App Sales keeps its own copy and never writes to the file.")
                        }
                    }
                    #endif
                } else {
                    Section {
                        Button("Sign In with \(assistant.name)", systemImage: "person.badge.key") {
                            let request = AIUsageAPI.claudeSignInRequest()
                            withAnimation {
                                signInRequest = request
                            }
                            openURL(request.url)
                        }
                    } footer: {
                        Text("Opens \(assistant.name) in your browser. App Sales asks only to read your limits — the sign-in is its own, and leaves the one your terminal uses alone.")
                    }

                    if signInRequest != nil {
                        Section {
                            TextField("Code", text: code)
                                .font(.footnote.monospaced())
                                #if canImport(UIKit)
                                .textInputAutocapitalization(.never)
                                #endif
                                .autocorrectionDisabled()
                        } header: {
                            Text("Paste Code")
                        } footer: {
                            Text("\(assistant.name) shows a code once you approve. Copy it and paste it here.")
                        }
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Connect \(assistant.name)")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        Task { await connect() }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connecting)
                }
            }
            #if os(macOS)
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    read(contentsOf: url)
                case .failure(let failure):
                    error = failure.localizedDescription
                }
            }
            .fileDialogDefaultDirectory(defaultDirectory)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    /// A code copied off a web page brings a line break with it as often as not, and no code
    /// contains whitespace — so take it out as it arrives rather than leaving it to be hunted for.
    private var code: Binding<String> {
        Binding {
            text
        } set: { newValue in
            text = newValue.filter { !$0.isWhitespace }
        }
    }

    /// The folder the sign-in lives in, so the picker opens on it rather than somewhere a name
    /// beginning with a dot is hidden.
    ///
    /// A sandboxed app's own idea of the home folder is its container, so the real one has to come
    /// from the account record. Only the picker's starting point depends on this — nothing is read
    /// until the reader chooses a file.
    private var defaultDirectory: URL? {
        guard let credentialsFile = assistant.credentialsFile,
              let home = getpwuid(getuid())?.pointee.pw_dir, let path = String(validatingCString: home) else { return nil }

        let directory = URL(filePath: path)
            .appending(path: credentialsFile)
            .deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: directory.path()) ? directory : nil
    }

    #if os(macOS)
    /// Fills the field with the file the reader picked, so connecting is the same one step it is
    /// for a paste — and so what was read is on screen if it turns out not to be a sign-in.
    private func read(contentsOf url: URL) {
        // A file the reader picked is only readable while its security scope is held open.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            error = AIUsageError.unreadableSignIn(assistant).localizedDescription
            return
        }
        text = contents
    }
    #endif

    private func connect() async {
        error = nil
        connecting = true
        defer { connecting = false }

        do {
            if let signInRequest {
                AIAssistants.shared.connect(try await AIUsageAPI.claudeSignIn(code: text, request: signInRequest))
            } else {
                try AIAssistants.shared.connect(assistant, with: text)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    List {
        AIUsageSection()
    }
}
