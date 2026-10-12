#!/usr/bin/env python3
# Builds the README art (assets/banner.svg, assets/demo.svg) from Flash's
# pixel rows in shell/zap.zsh. Render them to PNG with scripts/render-svg.sh.
import re, pathlib, html

root = pathlib.Path(__file__).resolve().parent.parent
src = (root / "shell/zap.zsh").read_text()
body = re.search(r"_zap_flash_load\(\) \{(.*?)\n\}", src, re.S).group(1)
idle = re.findall(r'"([.YOWKS]{16})"', re.search(r"local -a idle=\((.*?)\)", body, re.S).group(1))

def frame(name):
    rows = list(idle)
    for i, row in re.findall(name + r'\[(\d+)\]="([.YOWKS]{16})"', body):
        rows[int(i) - 1] = row
    return rows

PAL = {"Y": "#FFD400", "O": "#FF8A00", "W": "#FFF8D0", "K": "#1B1B20", "S": "#FFF1A0"}

def flash(rows, x, y, px):
    out = []
    for j, row in enumerate(rows):
        for i, c in enumerate(row):
            if c in PAL:
                out.append(f'<rect x="{x + i * px}" y="{y + j * px}" width="{px + 0.5}" height="{px + 0.5}" fill="{PAL[c]}"/>')
    return "\n".join(out)

FONTS = """<style>
@font-face{font-family:Clash;src:url('file://%s/Library/Fonts/ClashDisplay-Bold.otf')}
@font-face{font-family:Mono;src:url('file:///System/Applications/Utilities/Terminal.app/Contents/Resources/Fonts/SF-Mono-Regular.otf')}
@font-face{font-family:Mono;font-weight:700;src:url('file:///System/Applications/Utilities/Terminal.app/Contents/Resources/Fonts/SF-Mono-Bold.otf')}
.c{font-family:Clash}.m{font-family:Mono}
</style>""" % pathlib.Path.home()

def esc(s):
    return html.escape(s, quote=False)

# ---------- banner 1280x640 ----------
W, H = 1280, 640
banner = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
{FONTS}
<defs>
  <pattern id="dots" width="28" height="28" patternUnits="userSpaceOnUse"><circle cx="2" cy="2" r="1.3" fill="#fff" fill-opacity=".06"/></pattern>
  <radialGradient id="glow" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#FFC400" stop-opacity=".32"/><stop offset=".55" stop-color="#FF8A00" stop-opacity=".08"/><stop offset="1" stop-color="#FF8A00" stop-opacity="0"/></radialGradient>
  <linearGradient id="fade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0B0B0D" stop-opacity="0"/><stop offset="1" stop-color="#0B0B0D"/></linearGradient>
  <linearGradient id="word" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#C9C9D1"/></linearGradient>
  <filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="14" in="SourceAlpha" result="b"/><feFlood flood-color="#FFB800" flood-opacity=".45"/><feComposite in2="b" operator="in"/><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>
</defs>
<rect width="{W}" height="{H}" fill="#0B0B0D"/>
<rect width="{W}" height="{H}" fill="url(#dots)"/>
<rect y="{H - 200}" width="{W}" height="200" fill="url(#fade)"/>
<circle cx="290" cy="320" r="330" fill="url(#glow)"/>
<g filter="url(#soft)">{flash(frame("zap1"), 130, 140, 20)}</g>

<text x="540" y="318" class="c" font-size="176" letter-spacing="-5" fill="url(#word)">zap</text>
<text x="548" y="378" class="m" font-size="27" fill="#9A9AA4">say it in words. get the command.</text>

<g transform="translate(540,420)">
  <rect width="640" height="118" rx="16" fill="#141417" stroke="#2A2A30"/>
  <circle cx="26" cy="22" r="6" fill="#FF5F57"/><circle cx="46" cy="22" r="6" fill="#FEBC2E"/><circle cx="66" cy="22" r="6" fill="#28C840"/>
  <text x="26" y="66" class="m" font-size="22"><tspan fill="#FFD400">❯</tspan><tspan fill="#E8E8EE"> /zap kill whatever is on port 3000</tspan></text>
  <text x="26" y="99" class="m" font-size="22"><tspan fill="#FFD400">⚡</tspan><tspan fill="#FFFFFF" font-weight="700"> kill $(lsof -ti :3000)</tspan><tspan fill="#5F5F6A">  0.4s</tspan></text>
</g>
<text x="{W - 48}" y="{H - 34}" text-anchor="end" class="m" font-size="17" fill="#55555E">free · open source · macOS</text>
</svg>"""
(root / "assets/banner.svg").write_text(banner)

# ---------- demo terminal 1200x700 ----------
W, H = 1200, 640
lines = [
    ("prompt", "/zap convert every png in this folder to jpg"),
    ("cmd", 'for f in *.png; do sips -s format jpeg "$f" --out "${f%.png}.jpg"; done'),
    ("out", "/Users/louai/Desktop/shots/one.png"),
    ("out", "  /Users/louai/Desktop/shots/one.jpg"),
    ("gap", ""),
    ("prompt", "/zap delete every node_modules folder in ~/Projects"),
    ("risky", "find ~/Projects -name node_modules -type d -prune -exec rm -rf {} +"),
    ("warn", ""),
    ("ask", ""),
    ("gap", ""),
    ("prompt", "/zap what's eating my disk space?"),
]
y = 110
parts = []
for kind, text in lines:
    if kind == "prompt":
        parts.append(f'<text x="40" y="{y}" class="m" font-size="20"><tspan fill="#6FB8FF">~/Desktop</tspan><tspan fill="#FFD400"> ❯ </tspan><tspan fill="#E8E8EE">{esc(text)}</tspan></text>')
        y += 46
    elif kind == "cmd":
        parts.append(f'<text x="64" y="{y}" class="m" font-size="20"><tspan fill="#FFD400">⚡</tspan><tspan fill="#FFFFFF" font-weight="700"> {esc(text)}</tspan></text>')
        y += 40
    elif kind == "risky":
        parts.append(f'<text x="64" y="{y}" class="m" font-size="20"><tspan fill="#FF5F57">⚡</tspan><tspan fill="#FF6B63" font-weight="700"> {esc(text)}</tspan></text>')
        y += 40
    elif kind == "warn":
        parts.append(f'<text x="64" y="{y}" class="m" font-size="20"><tspan fill="#FF5F57" font-weight="700">careful:</tspan><tspan fill="#FF6B63"> this can delete or change things you can\'t get back.</tspan></text>')
        y += 30
    elif kind == "ask":
        parts.append(f'<text x="64" y="{y}" class="m" font-size="20" fill="#C8C8D0">type <tspan font-weight="700" fill="#fff">yes</tspan> to run it, <tspan font-weight="700" fill="#fff">e</tspan> to edit, anything else cancels: <tspan fill="#FFD400">▌</tspan></text>')
        y += 30
    elif kind == "out":
        parts.append(f'<text x="40" y="{y}" class="m" font-size="18" fill="#8A8A94">{esc(text)}</text>')
        y += 28
    else:
        y += 26
demo = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
{FONTS}
<rect width="{W}" height="{H}" rx="18" fill="#101013"/>
<rect x=".5" y=".5" width="{W - 1}" height="{H - 1}" rx="18" fill="none" stroke="#2A2A30"/>
<rect width="{W}" height="52" rx="18" fill="#18181C"/><rect y="34" width="{W}" height="18" fill="#18181C"/>
<line x1="0" y1="52" x2="{W}" y2="52" stroke="#2A2A30"/>
<circle cx="28" cy="26" r="7" fill="#FF5F57"/><circle cx="52" cy="26" r="7" fill="#FEBC2E"/><circle cx="76" cy="26" r="7" fill="#28C840"/>
<text x="{W / 2}" y="32" text-anchor="middle" class="m" font-size="15" fill="#77777F">zsh — 120×36</text>
{"".join(parts)}
<g>{flash(frame("zap2"), 70, y - 10, 7)}</g>
</svg>"""
(root / "assets/demo.svg").write_text(demo)
print("wrote assets/banner.svg and assets/demo.svg")
