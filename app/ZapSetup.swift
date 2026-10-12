// Zap.app — the setup window. Pick an AI and a model, check it answers,
// then install the /zap command for Terminal.

import SwiftUI
import AppKit

@main
struct ZapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            SetupView()
                .frame(width: 600, height: 720)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Look

enum Palette {
    static let bg = Color(red: 0.05, green: 0.05, blue: 0.06)
    static let card = Color(red: 0.09, green: 0.09, blue: 0.10)
    static let line = Color.white.opacity(0.08)
    static let yellow = Color(red: 1.0, green: 0.82, blue: 0.0)
    static let orange = Color(red: 1.0, green: 0.55, blue: 0.0)
    static let dim = Color.white.opacity(0.5)
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - AIs and their models

struct Model: Hashable {
    let id: String
    let label: String
}

struct Provider: Identifiable {
    let id: String
    let name: String
    let icon: String
    let tag: String
    let blurb: String
    let site: String
    let keyName: String?        // set for API-key providers, nil for command line tools
    let models: [Model]
}

let providers: [Provider] = [
    Provider(id: "groq", name: "Groq", icon: "bolt.fill", tag: "~0.5s · free",
             blurb: "The fastest. Free key, no card.", site: "https://console.groq.com/keys",
             keyName: "GROQ_API_KEY", models: [
                Model(id: "openai/gpt-oss-120b", label: "GPT-OSS 120B · smart"),
                Model(id: "openai/gpt-oss-20b", label: "GPT-OSS 20B · fastest"),
                Model(id: "moonshotai/kimi-k2-instruct-0905", label: "Kimi K2"),
             ]),
    Provider(id: "cerebras", name: "Cerebras", icon: "hare.fill", tag: "~0.5s · free",
             blurb: "Also very fast. Free key.", site: "https://cloud.cerebras.ai",
             keyName: "CEREBRAS_API_KEY", models: [
                Model(id: "gpt-oss-120b", label: "GPT-OSS 120B"),
                Model(id: "qwen-3-235b-a22b-instruct-2507", label: "Qwen 3 235B"),
             ]),
    Provider(id: "claude", name: "Claude Code", icon: "sparkle", tag: "smartest",
             blurb: "Uses your Claude plan. ~4s.", site: "https://docs.anthropic.com/en/docs/claude-code/setup",
             keyName: nil, models: [
                Model(id: "haiku", label: "Haiku · fastest"),
                Model(id: "sonnet", label: "Sonnet · balanced"),
                Model(id: "opus", label: "Opus · smartest"),
             ]),
    Provider(id: "ollama", name: "Ollama", icon: "laptopcomputer", tag: "offline",
             blurb: "Runs on your Mac. Private.", site: "https://ollama.com/download",
             keyName: nil, models: []),
    Provider(id: "codex", name: "Codex", icon: "chevron.left.forwardslash.chevron.right", tag: "ChatGPT plan",
             blurb: "OpenAI's command line tool.", site: "https://github.com/openai/codex",
             keyName: nil, models: [Model(id: "", label: "Default")]),
    Provider(id: "gemini", name: "Gemini CLI", icon: "diamond.fill", tag: "free",
             blurb: "Google's command line tool.", site: "https://github.com/google-gemini/gemini-cli",
             keyName: nil, models: [Model(id: "", label: "Default")]),
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
    @Published var selected = "groq"
    @Published var model = ""
    @Published var customModel = ""
    @Published var models: [Model] = []
    @Published var key = ""
    @Published var autoRun = true
    @Published var error: String?

    let resources = Bundle.main.resourcePath ?? "."
    let zapHome = NSHomeDirectory() + "/.zap"
    var configPath: String { zapHome + "/config" }
    var keysPath: String { zapHome + "/keys" }
    var ollamaModels: [Model] = []

    var provider: Provider { providers.first { $0.id == selected } ?? providers[0] }
    var chosenModel: String { model == "custom" ? customModel.trimmingCharacters(in: .whitespaces) : model }
    var modelLabel: String {
        models.first { $0.id == chosenModel }?.label.components(separatedBy: " · ").first
            ?? (chosenModel.isEmpty ? "default" : chosenModel)
    }

    func available(_ p: Provider) -> Bool { p.keyName != nil || found[p.id] != nil }

    func scan() async {
        let r = await Shell.run("for b in claude codex gemini ollama; do print -r -- \"$b=$(whence -p $b)\"; done", timeout: 20)
        var f: [String: String] = [:]
        for line in r.out.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, !parts[1].isEmpty { f[parts[0]] = parts[1] }
        }
        found = f

        if f["ollama"] != nil {
            let m = await Shell.run("ollama list 2>/dev/null | awk 'NR>1 {print $1}'", timeout: 15)
            ollamaModels = m.out.split(separator: "\n").map(String.init)
                .filter { !$0.contains("embed") }
                .map { Model(id: $0, label: $0.replacingOccurrences(of: ":latest", with: "")) }
        }

        let cfg = readConfig()
        if let p = cfg["ZAP_PROVIDER"], providers.contains(where: { $0.id == p }) {
            choose(p, keepModel: cfg["ZAP_MODEL"] ?? "")
            autoRun = cfg["ZAP_AUTORUN"] == "1"
            stage = .done
        } else {
            choose("groq")
            stage = .pick
        }
    }

    func choose(_ id: String, keepModel: String? = nil) {
        guard let p = providers.first(where: { $0.id == id }), available(p) else { return }
        selected = id
        error = nil
        models = id == "ollama" ? ollamaModels : p.models
        key = p.keyName.flatMap { readKeys()[$0] } ?? ""
        if let keep = keepModel, !keep.isEmpty {
            if !models.contains(where: { $0.id == keep }) { models.append(Model(id: keep, label: keep)) }
            model = keep
        } else {
            model = models.first?.id ?? ""
        }
        if p.keyName != nil, !key.isEmpty { Task { await refreshModels() } }
    }

    /// Asks Groq / Cerebras which models the key can use right now.
    func refreshModels() async {
        let p = provider
        guard p.keyName != nil, !key.isEmpty else { return }
        let base = p.id == "groq" ? "https://api.groq.com/openai/v1" : "https://api.cerebras.ai/v1"
        var req = URLRequest(url: URL(string: base + "/models")!)
        req.setValue("Bearer \(key.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return }
        let skip = ["whisper", "guard", "tts", "embed", "playai", "orpheus", "compound", "allam"]
        let live = list.compactMap { $0["id"] as? String }
            .filter { id in !skip.contains { id.lowercased().contains($0) } }
            .sorted()
        guard selected == p.id, !live.isEmpty else { return }
        var merged = p.models.filter { live.contains($0.id) }
        merged += live.filter { id in !merged.contains { $0.id == id } }.map { Model(id: $0, label: $0) }
        models = merged
        if !models.contains(where: { $0.id == model }) && model != "custom" { model = models.first?.id ?? "" }
    }

    func connect() async {
        let p = provider
        error = nil

        if let name = p.keyName {
            let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !k.isEmpty else { error = "Paste your \(p.name) key first. It's free: click “get a free key”."; return }
            saveKey(name, k)
        }

        if p.id == "claude", !(await claudeSignedIn()) {
            await signInToClaude()
            guard await claudeSignedIn() else {
                if stage == .signingIn { error = "Didn't see a sign-in. Click Connect to try again." }
                stage = .pick
                return
            }
        }

        stage = .testing
        let m = chosenModel
        let test = await Shell.run("""
            ZAP_PROVIDER=\(p.id) ZAP_MODEL=\(Shell.quote(m))
            source \(Shell.quote(resources + "/zap.zsh"))
            _zap_ask 'Reply with only the word: ready'
            """, timeout: 180)

        guard test.ok, !test.out.isEmpty else {
            error = hint(for: p, output: test.out)
            stage = .pick
            return
        }

        let install = await Shell.run("zsh \(Shell.quote(resources + "/install.sh")) --provider \(p.id) --model \(Shell.quote(m)) --auto \(autoRun ? 1 : 0)")
        guard install.ok else {
            error = install.out
            stage = .pick
            return
        }
        stage = .done
    }

    func claudeSignedIn() async -> Bool {
        let r = await Shell.run("claude auth status", timeout: 20)
        return r.out.replacingOccurrences(of: " ", with: "").contains("\"loggedIn\":true")
    }

    /// Opens `claude auth login` in Terminal (it needs a real terminal for the
    /// browser hand-off) and waits up to 5 minutes for it to finish.
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
            if stage != .signingIn { return }
            if await claudeSignedIn() { return }
        }
    }

    func setAutoRun(_ on: Bool) {
        autoRun = on
        var cfg = readConfig()
        guard !cfg.isEmpty else { return }
        cfg["ZAP_AUTORUN"] = on ? "1" : "0"
        let text = ["ZAP_PROVIDER", "ZAP_MODEL", "ZAP_AUTORUN"].map { "\($0)=\(cfg[$0] ?? "")" }.joined(separator: "\n") + "\n"
        try? text.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    func uninstall() async {
        _ = await Shell.run("zsh \(Shell.quote(resources + "/install.sh")) --uninstall")
        choose(selected)
        stage = .pick
    }

    // ~/.zap/config and ~/.zap/keys are plain NAME=value lines
    private func readPairs(_ path: String) -> [String: String] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let p = line.split(separator: "=", maxSplits: 1).map(String.init)
            if let k = p.first { out[k] = p.count > 1 ? p[1] : "" }
        }
        return out
    }

    private func readConfig() -> [String: String] { readPairs(configPath) }
    private func readKeys() -> [String: String] { readPairs(keysPath) }

    private func saveKey(_ name: String, _ value: String) {
        var keys = readKeys()
        keys[name] = value
        try? FileManager.default.createDirectory(atPath: zapHome, withIntermediateDirectories: true)
        let text = keys.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
        FileManager.default.createFile(atPath: keysPath, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600])
    }

    private func hint(for p: Provider, output: String) -> String {
        let tail = output.split(separator: "\n").suffix(3).joined(separator: "\n")
        let lower = output.lowercased()
        if p.keyName != nil && (lower.contains("invalid") || lower.contains("401") || lower.contains("api key")) {
            return "\(p.name) didn't accept that key. Copy it again from \(p.site)"
        }
        if lower.contains("login") || lower.contains("log in") || lower.contains("auth") {
            return "\(p.name) isn't signed in. Open Terminal, run `\(p.id)` once, then try again."
        }
        if p.id == "ollama" && (lower.contains("connect") || lower.contains("refused")) {
            return "Ollama isn't running. Open the Ollama app, then try again."
        }
        return tail.isEmpty ? "No answer came back. Try again, or pick another AI." : tail
    }
}

// MARK: - Flash

struct FlashView: View {
    var size: CGFloat = 64
    private static let sequence = ["idle", "zap1", "zap2", "idle", "zap1", "zap2", "blink", "idle", "zap1", "zap2", "wink", "wink"]
    private static let frames: [String: NSImage] = {
        var out: [String: NSImage] = [:]
        for name in Set(sequence) {
            if let url = Bundle.main.url(forResource: "flash-\(name)", withExtension: "png"),
               let img = NSImage(contentsOf: url) { out[name] = img }
        }
        return out
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.11)) { context in
            let i = Int(context.date.timeIntervalSinceReferenceDate / 0.11) % Self.sequence.count
            if let img = Self.frames[Self.sequence[i]] {
                Image(nsImage: img).interpolation(.none).resizable()
                    .aspectRatio(contentMode: .fit).frame(width: size, height: size * 20 / 18)
            }
        }
    }
}

// MARK: - Views

struct SetupView: View {
    @StateObject private var setup = Setup()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.line)
            Group {
                switch setup.stage {
                case .scanning:  busy("Looking around your Mac…")
                case .pick:      pick
                case .signingIn: signingIn
                case .testing:   busy("Making sure \(setup.provider.name) answers…")
                case .done:      done
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxHeight: .infinity)
        }
        .background(Palette.bg)
        .task { await setup.scan() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            FlashView(size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("zap").font(.rounded(30, .heavy))
                Text("say it in words, get the command")
                    .font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.dim)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 18)
    }

    private func busy(_ text: String) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(Palette.yellow)
            Text(text).foregroundStyle(Palette.dim)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Palette.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var field: some View {
        RoundedRectangle(cornerRadius: 8).fill(Palette.card)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line))
    }

    // MARK: pick

    private var pick: some View {
        VStack(alignment: .leading, spacing: 14) {
            label("Brain")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(providers) { card($0) }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    label("Model")
                    modelPicker
                }
                .frame(maxWidth: .infinity)
                if let keyName = setup.provider.keyName {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            label("Key")
                            Link("get a free key ↗", destination: URL(string: setup.provider.site)!)
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.yellow)
                        }
                        SecureField(keyName, text: $setup.key)
                            .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                            .padding(8).background(field)
                            .onSubmit { Task { await setup.refreshModels() } }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            switchRow

            if let e = setup.error {
                Text(e).font(.callout).foregroundStyle(Color.red.opacity(0.9))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            bigButton("Connect \(setup.provider.name)") { Task { await setup.connect() } }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                ForEach(setup.models, id: \.self) { m in
                    Button(m.label) { setup.model = m.id }
                }
                Divider()
                Button("Other…") { setup.model = "custom" }
            } label: {
                HStack {
                    Text(setup.model == "custom" ? "Other…" : (setup.models.first { $0.id == setup.model }?.label ?? "Default"))
                        .font(.system(size: 13, design: .monospaced)).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(Palette.dim)
                }
                .padding(8).background(field)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .frame(maxWidth: .infinity)

            if setup.model == "custom" {
                TextField("model name", text: $setup.customModel)
                    .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                    .padding(8).background(field)
            }
        }
    }

    private func card(_ p: Provider) -> some View {
        let ok = setup.available(p)
        let on = setup.selected == p.id
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: p.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? .black : Palette.yellow)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? Palette.yellow : Palette.yellow.opacity(0.1)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(p.name).font(.rounded(14, .bold))
                    Text(p.tag).font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(on ? Palette.yellow : Palette.dim)
                }
                if ok {
                    Text(p.blurb).font(.system(size: 11)).foregroundStyle(Palette.dim).lineLimit(1)
                } else {
                    Link("not installed · get it ↗", destination: URL(string: p.site)!)
                        .font(.system(size: 11)).foregroundStyle(Palette.dim)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12).fill(on ? Palette.yellow.opacity(0.08) : Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Palette.yellow.opacity(0.7) : Palette.line, lineWidth: on ? 1.5 : 1))
        .opacity(ok ? 1 : 0.45)
        .contentShape(Rectangle())
        .onTapGesture { setup.choose(p.id) }
    }

    private var switchRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Run safe commands right away").font(.rounded(13, .semibold))
                Text("risky ones like rm or sudo still ask first").font(.system(size: 11)).foregroundStyle(Palette.dim)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { setup.autoRun }, set: { setup.setAutoRun($0) }))
                .labelsHidden().toggleStyle(.switch).tint(Palette.yellow)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
    }

    private func bigButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.rounded(15, .bold)).foregroundStyle(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(
                    LinearGradient(colors: [Palette.yellow, Palette.orange], startPoint: .leading, endPoint: .trailing)))
        }
        .buttonStyle(.plain)
    }

    // MARK: sign-in

    private var signingIn: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(Palette.yellow)
            Text("Sign in to Claude in your browser").font(.rounded(17, .bold))
            Text("Zap opened the sign-in for you. Once you're done there, it connects by itself.")
                .multilineTextAlignment(.center).foregroundStyle(Palette.dim)
            Button("Cancel") { setup.stage = .pick }.buttonStyle(.borderless).padding(.top, 6)
        }
    }

    // MARK: done

    private var done: some View {
        VStack(spacing: 18) {
            FlashView(size: 96).padding(.top, 6)
            VStack(spacing: 6) {
                Text("Flash is ready.").font(.rounded(24, .heavy))
                HStack(spacing: 6) {
                    chip(setup.provider.name)
                    chip(setup.modelLabel)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                label("Try it in a new Terminal window")
                HStack {
                    Text("/zap ").foregroundColor(Palette.yellow) + Text("show the 10 biggest files in Downloads")
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("/zap show the 10 biggest files in Downloads", forType: .string)
                    } label: { Image(systemName: "doc.on.doc").foregroundStyle(Palette.dim) }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 13, design: .monospaced))
                .padding(12).background(field)
            }

            switchRow

            Spacer(minLength: 0)

            bigButton("Open Terminal") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
            }
            HStack {
                Button("Change brain or model") { setup.error = nil; setup.stage = .pick }
                Spacer()
                Button("Uninstall") { Task { await setup.uninstall() } }.foregroundStyle(Color.red.opacity(0.8))
            }
            .buttonStyle(.borderless).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.dim)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Palette.yellow.opacity(0.12)))
            .foregroundStyle(Palette.yellow)
    }
}
