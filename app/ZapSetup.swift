// Zap.app — the setup window. Finds the AI tools on this Mac, checks the one
// you pick actually answers, then installs the /zap command for Terminal.

import SwiftUI
import AppKit

@main
struct ZapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            SetupView()
                .frame(width: 500, height: 620)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Providers

struct Provider: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let site: String
    let suggestedModel: String
}

let providers = [
    Provider(id: "claude", name: "Claude Code", blurb: "Anthropic's CLI. Run `claude` once to log in.",
             site: "https://docs.anthropic.com/en/docs/claude-code/setup", suggestedModel: "sonnet"),
    Provider(id: "codex", name: "Codex", blurb: "OpenAI's CLI. Works with a ChatGPT account.",
             site: "https://github.com/openai/codex", suggestedModel: ""),
    Provider(id: "gemini", name: "Gemini CLI", blurb: "Google's CLI. Free with a Google account.",
             site: "https://github.com/google-gemini/gemini-cli", suggestedModel: ""),
    Provider(id: "ollama", name: "Ollama", blurb: "Runs models on your Mac. Free, works offline.",
             site: "https://ollama.com/download", suggestedModel: ""),
]

// MARK: - Shell

enum Shell {
    private static let marker = "__zap_out__"

    /// Runs through a login + interactive zsh so PATH is the same one Terminal sees.
    static func run(_ command: String, timeout: TimeInterval = 120) async -> (ok: Bool, out: String) {
        await withCheckedContinuation { done in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-lic", "print -r -- \(marker); \(command)"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch {
                    done.resume(returning: (false, error.localizedDescription))
                    return
                }
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                killer.cancel()

                // drop whatever .zshrc printed before our command started
                var s = String(decoding: data, as: UTF8.self)
                if let r = s.range(of: marker + "\n") { s = String(s[r.upperBound...]) }
                done.resume(returning: (p.terminationStatus == 0, s.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }

    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - State

@MainActor
final class Setup: ObservableObject {
    enum Stage { case scanning, pick, signingIn, testing, done }

    @Published var stage = Stage.scanning
    @Published var found: [String: String] = [:]
    @Published var selected: String?
    @Published var model = ""
    @Published var ollamaModels: [String] = []
    @Published var error: String?
    @Published var active = ""
    @Published var autoRun = false
    private var signInTask: Task<Void, Never>?

    let resources = Bundle.main.resourcePath ?? "."
    let configPath = NSHomeDirectory() + "/.zap/config"

    var selectedProvider: Provider? { providers.first { $0.id == selected } }

    func scan() async {
        let r = await Shell.run("for b in claude codex gemini ollama; do print -r -- \"$b=$(whence -p $b)\"; done", timeout: 20)
        var f: [String: String] = [:]
        for line in r.out.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, !parts[1].isEmpty, providers.contains(where: { $0.id == parts[0] }) {
                f[parts[0]] = parts[1]
            }
        }
        found = f

        if f["ollama"] != nil {
            let m = await Shell.run("ollama list 2>/dev/null | awk 'NR>1 {print $1}'", timeout: 15)
            ollamaModels = m.out.split(separator: "\n").map(String.init).filter { !$0.contains("embed") }
        }

        if let saved = try? String(contentsOfFile: configPath, encoding: .utf8) {
            let cfg = Dictionary(saved.split(separator: "\n").compactMap { line -> (String, String)? in
                let p = line.split(separator: "=", maxSplits: 1).map(String.init)
                return p.count == 2 ? (p[0], p[1]) : (p.first.map { ($0, "") })
            }, uniquingKeysWith: { a, _ in a })
            selected = cfg["ZAP_PROVIDER"]
            model = cfg["ZAP_MODEL"] ?? ""
            autoRun = cfg["ZAP_AUTORUN"] == "1"
            updateActive()
            stage = .done
        } else {
            choose(providers.first { f[$0.id] != nil }?.id)
            stage = .pick
        }
    }

    func choose(_ id: String?) {
        guard let id, found[id] != nil else { return }
        selected = id
        error = nil
        if id == "ollama" {
            model = ollamaModels.first ?? ""
        } else {
            model = providers.first { $0.id == id }?.suggestedModel ?? ""
        }
    }

    func connect() async {
        guard let id = selected else { return }
        stage = .testing
        error = nil

        // Claude Code: sign in first if needed, then carry on by ourselves
        if id == "claude", !(await claudeSignedIn()) {
            await signInToClaude()
            guard await claudeSignedIn() else {
                if stage == .signingIn {
                    error = "Didn't see a sign-in. Click Connect to try again."
                    stage = .pick
                }
                return
            }
            stage = .testing
        }

        let m = model.trimmingCharacters(in: .whitespaces)
        let test = await Shell.run("""
            ZAP_PROVIDER=\(id) ZAP_MODEL=\(Shell.quote(m))
            source \(Shell.quote(resources + "/zap.zsh"))
            _zap_ask 'Reply with only the word: ready'
            """, timeout: 180)

        guard test.ok, !test.out.isEmpty else {
            error = hint(for: id, output: test.out)
            stage = .pick
            return
        }

        let install = await Shell.run("zsh \(Shell.quote(resources + "/install.sh")) --provider \(id) --model \(Shell.quote(m)) --auto \(autoRun ? 1 : 0)")
        guard install.ok else {
            error = install.out
            stage = .pick
            return
        }
        updateActive()
        stage = .done
    }

    func claudeSignedIn() async -> Bool {
        let r = await Shell.run("claude auth status", timeout: 20)
        return r.out.replacingOccurrences(of: " ", with: "").contains("\"loggedIn\":true")
    }

    /// Opens `claude auth login` in a Terminal window (it needs a real terminal
    /// for the browser hand-off) and waits up to 5 minutes for it to finish.
    func signInToClaude() async {
        stage = .signingIn
        let bin = found["claude"] ?? "claude"
        let script = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("zap-sign-in.command")
        let body = """
            #!/bin/zsh
            clear
            print "Sign in to Claude in the browser window that opens."
            print "Zap will pick it up by itself once you're done.\\n"
            \(Shell.quote(bin)) auth login
            print "\\nAll set. You can close this window."
            """
        try? body.write(to: script, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        NSWorkspace.shared.open(script)

        for _ in 0..<100 {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if stage != .signingIn { return }   // cancelled
            if await claudeSignedIn() { return }
        }
    }

    func cancelSignIn() {
        stage = .pick
    }

    func setAutoRun(_ on: Bool) {
        autoRun = on
        let path = configPath
        guard var text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        var lines = text.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("ZAP_AUTORUN=") }
        lines.append("ZAP_AUTORUN=\(on ? 1 : 0)")
        text = lines.joined(separator: "\n") + "\n"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func uninstall() async {
        _ = await Shell.run("zsh \(Shell.quote(resources + "/install.sh")) --uninstall")
        active = ""
        choose(selected)
        stage = .pick
    }

    private func updateActive() {
        let name = selectedProvider?.name ?? selected ?? "?"
        active = model.isEmpty ? name : "\(name) · \(model)"
    }

    private func hint(for id: String, output: String) -> String {
        let tail = output.split(separator: "\n").suffix(4).joined(separator: "\n")
        let lower = output.lowercased()
        if lower.contains("login") || lower.contains("log in") || lower.contains("auth") || lower.contains("api key") {
            return "\(selectedProvider?.name ?? id) isn't logged in. Open Terminal, run `\(id)` once, sign in, then try again.\n\n\(tail)"
        }
        if id == "ollama" && (lower.contains("connect") || lower.contains("refused")) {
            return "Ollama isn't running. Open the Ollama app, then try again."
        }
        return tail.isEmpty ? "No answer came back. Try again, or pick another AI." : tail
    }
}

// MARK: - Views

let accent = Color(red: 1.0, green: 0.78, blue: 0.1)
let card = Color.white.opacity(0.05)

struct SetupView: View {
    @StateObject private var setup = Setup()

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch setup.stage {
                case .scanning: busy("Looking for AI tools on this Mac…")
                case .pick:     pick
                case .signingIn: signingIn
                case .testing:  busy("Checking that \(setup.selectedProvider?.name ?? "it") answers…")
                case .done:     done
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(28)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
        .task { await setup.scan() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            if let url = Bundle.main.url(forResource: "logo", withExtension: "png"), let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().frame(width: 84, height: 84)
            }
            Text("Zap").font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Say what you want in Terminal. Zap writes the command.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(.bottom, 22)
    }

    private func busy(_ text: String) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private var pick: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which AI should Zap use?").font(.headline)

            ForEach(providers) { p in row(p) }

            if setup.selected == "ollama" {
                if setup.ollamaModels.isEmpty {
                    Text("No models yet. In Terminal: ollama pull llama3.2").font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Model", selection: $setup.model) {
                        ForEach(setup.ollamaModels, id: \.self) { Text($0).tag($0) }
                    }
                }
            } else if setup.selected != nil {
                HStack {
                    Text("Model").foregroundStyle(.secondary)
                    TextField("default", text: $setup.model).textFieldStyle(.roundedBorder)
                }
                .font(.callout)
            }

            if let e = setup.error {
                Text(e).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            autoRunSwitch($setup.autoRun)

            if setup.found.isEmpty {
                Text("Nothing found. Install one of these, then reopen Zap.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button {
                Task { await setup.connect() }
            } label: {
                Text("Connect").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .foregroundStyle(.black)
            .keyboardShortcut(.defaultAction)
            .disabled(setup.selected == nil)
        }
    }

    private func row(_ p: Provider) -> some View {
        let installed = setup.found[p.id] != nil
        let on = setup.selected == p.id
        return HStack(spacing: 12) {
            Image(systemName: on ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(on ? accent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).fontWeight(.semibold)
                Text(p.blurb).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if installed {
                Text("found").font(.caption).foregroundStyle(.green)
            } else {
                Link("get it", destination: URL(string: p.site)!).font(.caption)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(on ? accent.opacity(0.12) : card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? accent.opacity(0.6) : .clear))
        .opacity(installed ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture { setup.choose(p.id) }
    }

    private func autoRunSwitch(_ on: Binding<Bool>) -> some View {
        HStack {
            Text("Run safe commands without asking").font(.callout)
            Spacer()
            Toggle("", isOn: on).labelsHidden().toggleStyle(.switch).tint(accent)
        }
    }

    private var signingIn: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Sign in to Claude in your browser").font(.headline)
            Text("Zap opened the sign-in for you. Once you're done there, it connects by itself.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Cancel") { setup.cancelSignIn() }.buttonStyle(.borderless).padding(.top, 6)
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(accent)
            Text("Zap is ready").font(.title2.bold())
            Text("Using \(setup.active)").foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Open a new Terminal window and type:").font(.callout).foregroundStyle(.secondary)
                Text("/zap show the 10 biggest files in Downloads")
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(card))
                    .textSelection(.enabled)
            }

            autoRunSwitch(Binding(get: { setup.autoRun }, set: { setup.setAutoRun($0) }))
            Text("Risky ones like rm or sudo still ask first.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
            } label: {
                Text("Open Terminal").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .foregroundStyle(.black)

            HStack {
                Button("Switch AI") { setup.error = nil; setup.stage = .pick }
                Spacer()
                Button("Uninstall", role: .destructive) { Task { await setup.uninstall() } }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }
}
