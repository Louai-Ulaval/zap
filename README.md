<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo/zap-wordmark-dark.png">
    <img src="assets/logo/zap-wordmark-light.png" alt="zap" width="420">
  </picture>
</p>

<p align="center">Say what you want in Terminal. Zap writes the command, you hit <code>y</code>.</p>

---

I kept googling the same things: how to find big files, how to kill whatever is on port 3000, the right ffmpeg flags. So I made this. You type what you want in plain words and Zap asks the AI you already have on your Mac (Claude Code, Codex, Gemini CLI or Ollama) to write the command. You see it before anything runs.

```
$ /zap find every video over 1GB on my desktop

  ⚡ find ~/Desktop -type f \( -iname '*.mp4' -o -iname '*.mov' \) -size +1G

  run it? [y/N/e] y
/Users/me/Desktop/render_final_v3.mov
```

## Meet Flash

<img src="assets/flash/flash.gif" width="160" align="right">

Flash lives in your terminal. While the AI is working out your command he crackles and blinks next to your prompt, then gets out of the way the moment the answer shows up. Type `zap` on its own to say hi.

## Install

1. Download `Zap.dmg` from [Releases](../../releases) and drag Zap into Applications.
2. Open it. The first time, macOS will block it because it isn't from the App Store: go to **System Settings → Privacy & Security** and click **Open Anyway**.
3. Pick the AI you want to use and click **Connect**. If you picked Claude Code and you're not signed in, Zap opens the sign-in for you and carries on once you're done.
4. Open a new Terminal window and type `/zap` followed by whatever you want.

Pick a brain and a model in the app. Groq is the default because it's free and answers in about half a second. Groq and Cerebras need a free key (paste it in the app; it's stored in `~/.zap/keys`, readable only by you). The others use tools you already have installed:

| AI | Speed | Cost | Get it |
|---|---|---|---|
| Groq | ~0.5 s | free key | [console.groq.com/keys](https://console.groq.com/keys) |
| Cerebras | ~0.5 s | free key | [cloud.cerebras.ai](https://cloud.cerebras.ai) |
| Claude Code | ~4 s | Claude subscription | [docs](https://docs.anthropic.com/en/docs/claude-code/setup) |
| Codex | slow | ChatGPT account | [github.com/openai/codex](https://github.com/openai/codex) |
| Gemini CLI | slow | free with a Google account | [github.com/google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli) |
| Ollama | ~2 s | free, runs offline | [ollama.com](https://ollama.com/download) |

### Without the app

```sh
git clone https://github.com/<you>/zap.git
cd zap
./scripts/install.sh --provider ollama --model llama3.2
```

## Using it

```
/zap convert all the pngs here to jpg
/zap what's using port 3000? kill it
/zap make a folder for each month of 2026
/zap zip this folder without the node_modules
```

When the command shows up:

- `y` runs it
- `e` lets you edit it first
- anything else cancels

If you'd rather not be asked every time, turn on **Run safe commands without asking** in the app (or `zap --auto on`). Safe commands then run right away. Anything risky still stops and asks.

A few things it does for you:

- **Shows before it runs.** Nothing happens until you say so.
- **Warns you about risky stuff.** Anything with `rm`, `sudo`, `dd`, `git push --force` and similar shows in red, and you have to type `yes` in full.
- **Fixes its own mistakes.** If the command fails, Zap can send the error back and get a fixed version (up to 3 tries).
- **Knows where you are.** It sees your current folder and which tools you have installed, so it won't use `ffmpeg` if you don't have it.
- **Plays nice with history.** The real command lands in your shell history, so arrow-up gives it back next time.
- **Works with `cd`.** Zap runs in your shell, so `/zap go to my downloads` actually takes you there.

Other commands:

```
zap --use groq openai/gpt-oss-20b   switch brain/model (or open Zap.app)
zap --auto on                       run safe commands without asking
zap --history                       what you ran lately
zap --version
```

Settings are in `~/.zap/config`.

## Uninstall

Open Zap.app and click **Uninstall**, or run `./scripts/install.sh --uninstall`. It removes `~/.zap` and the two lines it added to `~/.zshrc`.

## Build it yourself

You need the Xcode command line tools (`xcode-select --install`).

```sh
./scripts/build-dmg.sh
```

That gives you `build/Zap.app` and `build/Zap-<version>.dmg`, built for both Apple Silicon and Intel.

## How it works

- `shell/zap.zsh` is everything that happens in Terminal. It's plain zsh, nothing to compile. Flash is drawn there too, one character per pixel, using half blocks so two pixels fit in one row (`scripts/render-flash.py` turns the same rows into the PNG and GIF).
- `app/ZapSetup.swift` is the setup window. It finds which AI tools you have, checks the one you pick actually answers, then runs `scripts/install.sh`.
- `/zap` works because Zap hooks into the Enter key: a line starting with `/zap` gets quoted and passed to the `zap` function before zsh sees it. That's also why you can type apostrophes and question marks without quotes.

Only zsh is supported for now (it's been the default on macOS since Catalina).

## License

MIT
