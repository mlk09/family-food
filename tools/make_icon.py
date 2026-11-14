# Draws the app icon (chef hat + AI sparkles on a saffron→tomato→pink gradient).
# Usage: python3 tools/make_icon.py assets/icon && dart run flutter_launcher_icons
import sys
from PIL import Image, ImageDraw, ImageFilter
S = 4; N = 1024 * S
out = sys.argv[1]

def gradient():
    a, b, c = (255, 170, 60), (255, 92, 77), (226, 64, 128)
    g = Image.new('RGB', (N, N))
    d = ImageDraw.Draw(g)
    for i in range(0, 2 * N, S):
        t = i / (2 * N)
        col = tuple(int((a[k] + (b[k] - a[k]) * t * 2) if t < .5 else (b[k] + (c[k] - b[k]) * (t - .5) * 2)) for k in range(3))
        d.line([(i, 0), (0, i)], fill=col, width=S * 2)
    return g

def star(d, cx, cy, r, fill):
    k = r * 0.28
    d.polygon([(cx, cy - r), (cx + k, cy - k), (cx + r, cy), (cx + k, cy + k), (cx, cy + r), (cx - k, cy + k), (cx - r, cy), (cx - k, cy - k)], fill=fill)

def hat(scale=1.0):
    fg = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    def p(x): return int((512 + (x - 512) * scale) * S)
    def r(v): return int(v * scale * S)
    # soft shadow
    sh = Image.new('RGBA', (N, N), (0, 0, 0, 0)); sd = ImageDraw.Draw(sh)
    sd.ellipse([p(360), p(712), p(664), p(772)], fill=(90, 20, 30, 70))
    sh = sh.filter(ImageFilter.GaussianBlur(28 * S * scale))
    fg.alpha_composite(sh)
    d = ImageDraw.Draw(fg)
    white, cream, pleat = (255, 255, 255, 255), (255, 236, 214, 255), (246, 222, 204, 255)
    for cx, cy, rr in [(392, 448, 128), (512, 372, 158), (632, 448, 128), (452, 400, 120), (572, 400, 120)]:
        d.ellipse([p(cx - rr), p(cy - rr), p(cx + rr), p(cy + rr)], fill=white)
    d.polygon([(p(318), p(470)), (p(706), p(470)), (p(660), p(650)), (p(364), p(650))], fill=white)
    for x in (442, 512, 582):
        d.rounded_rectangle([p(x - 7), p(520), p(x + 7), p(640)], radius=r(7), fill=pleat)
    d.rounded_rectangle([p(352), p(630), p(672), p(740)], radius=r(34), fill=cream)
    d.rounded_rectangle([p(352), p(678), p(672), p(694)], radius=r(10), fill=(255, 166, 61, 255))
    star(d, p(724), p(282), r(74), (255, 214, 74, 255))
    star(d, p(300), p(300), r(38), (255, 240, 180, 255))
    star(d, p(760), p(420), r(26), (255, 240, 180, 255))
    return fg

bg = gradient().convert('RGBA')
full = bg.copy(); full.alpha_composite(hat(1.0))
full.resize((1024, 1024), Image.LANCZOS).convert('RGB').save(out + '/app_icon.png')
hat(1.0).resize((1024, 1024), Image.LANCZOS).save(out + '/app_icon_foreground.png')
bg.resize((1024, 1024), Image.LANCZOS).convert('RGB').save(out + '/app_icon_background.png')
