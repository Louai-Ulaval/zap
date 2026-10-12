#!/usr/bin/env python3
# Renders Flash from the pixel rows in shell/zap.zsh into assets/flash/
# (a still PNG for the app and an animated GIF for the README). Needs Pillow.
import re, pathlib
from PIL import Image

root = pathlib.Path(__file__).resolve().parent.parent
src = (root / "shell/zap.zsh").read_text()
body = re.search(r"_zap_flash_load\(\) \{(.*?)\n\}", src, re.S).group(1)

pal = {"Y": (255, 215, 0), "O": (255, 135, 0), "W": (255, 255, 215),
       "K": (38, 38, 38), "S": (255, 255, 175)}
idle = re.findall(r'"([.YOWKS]{16})"', re.search(r"local -a idle=\((.*?)\)", body, re.S).group(1))
frames = {"idle": idle}
for name in ("blink", "wink", "zap1", "zap2"):
    rows = list(idle)
    for i, row in re.findall(name + r'\[(\d+)\]="([.YOWKS]{16})"', body):
        rows[int(i) - 1] = row
    frames[name] = rows

def draw(rows, scale, bg=None):
    w, h = len(rows[0]) + 2, len(rows) + 2
    im = Image.new("RGBA", (w * scale, h * scale), bg or (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            if c in pal:
                im.paste(pal[c] + (255,), ((x + 1) * scale, (y + 1) * scale, (x + 2) * scale, (y + 2) * scale))
    return im

out = root / "assets/flash"
out.mkdir(parents=True, exist_ok=True)
draw(frames["wink"], 32).save(out / "flash.png")

seq = ["idle", "zap1", "zap2", "idle", "zap1", "zap2", "blink", "idle", "zap1", "zap2", "wink", "wink"]
gif = [draw(frames[n], 16, (13, 13, 15, 255)).convert("RGB") for n in seq]
gif[0].save(out / "flash.gif", save_all=True, append_images=gif[1:], duration=110, loop=0)
print("wrote", out / "flash.png", "and", out / "flash.gif")
