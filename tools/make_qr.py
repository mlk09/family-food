#!/usr/bin/env python3
"""Generate the install QR code for Family Food Assistant.

Usage:
    pip install "qrcode[pil]"
    python3 tools/make_qr.py https://your-deployed-site.example.com/

Outputs (in ./qr_output/ by default):
    family_food_assistant_qr.png   – high-resolution QR code with logo
    qr_print.html                  – printable "Scan to Install" page

The URL must be the PUBLIC, deployed download landing page. Localhost, private
network addresses and plain http:// are rejected because they will not work
on other people's phones.
"""
import argparse
import base64
import io
import ipaddress
import pathlib
import sys
from urllib.parse import urlparse

try:
    import qrcode
    from qrcode.constants import ERROR_CORRECT_H
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit('Missing dependency. Run:  pip install "qrcode[pil]"')

ROOT = pathlib.Path(__file__).resolve().parent.parent
ICON = ROOT / "assets" / "icon" / "app_icon.png"


def validate(url: str) -> str:
    u = urlparse(url.strip())
    if u.scheme != "https":
        raise ValueError("Use an https:// URL of your deployed download page.")
    host = (u.hostname or "").lower()
    if not host or host in {"localhost"} or host.endswith(".local") or "your_deployed" in url.lower() or "example.com" in host:
        raise ValueError(f"'{host}' is not a real public address. Deploy the download page first.")
    try:
        ip = ipaddress.ip_address(host)
        if ip.is_private or ip.is_loopback or ip.is_link_local:
            raise ValueError(f"{host} is a private/local address and won't work on other phones.")
    except ValueError as e:
        if "private" in str(e):
            raise
    return url.strip()


def make_qr(url: str) -> Image.Image:
    qr = qrcode.QRCode(error_correction=ERROR_CORRECT_H, box_size=20, border=3)
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(fill_color="#2A1E17", back_color="white").convert("RGB")
    if ICON.exists():  # logo in the centre (H error correction tolerates ~30% coverage)
        logo = Image.open(ICON).convert("RGBA")
        size = img.size[0] // 5
        logo = logo.resize((size, size), Image.LANCZOS)
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, size, size], radius=size // 4, fill=255)
        pad = size // 10
        plate = Image.new("RGB", (size + 2 * pad, size + 2 * pad), "white")
        pos = ((img.size[0] - plate.size[0]) // 2, (img.size[1] - plate.size[1]) // 2)
        img.paste(plate, pos)
        img.paste(logo, (pos[0] + pad, pos[1] + pad), mask)
    return img


PRINT_HTML = """<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><title>Family Food Assistant – Scan to Install</title>
<style>
  @page {{ size: A4; margin: 18mm; }}
  body {{ font-family: Outfit, system-ui, sans-serif; text-align: center; color: #2A1E17; margin: 0; padding: 40px 20px; }}
  h1 {{ font-size: 38px; margin: 0 0 6px; letter-spacing: .5px; }}
  h1 span {{ color: #FF6A3D; }}
  h2 {{ font-size: 26px; font-weight: 600; margin: 0 0 28px; color: #8A7568; }}
  img.qr {{ width: 360px; height: 360px; border: 10px solid #FFE2CC; border-radius: 28px; }}
  p {{ font-size: 18px; margin: 22px 0 4px; }}
  .url {{ font-size: 15px; color: #8A7568; word-break: break-all; }}
  .steps {{ display: flex; justify-content: center; gap: 28px; margin-top: 28px; font-size: 16px; }}
  .steps div span {{ display: block; font-size: 34px; }}
</style></head>
<body>
  <h1>Family <span>Food</span> Assistant</h1>
  <h2>Scan to Install</h2>
  <img class="qr" src="data:image/png;base64,{b64}" alt="QR code to install Family Food Assistant">
  <p>🍳 Your family's smart kitchen assistant</p>
  <div class="url">{url}</div>
  <div class="steps">
    <div><span>📷</span>Open your camera</div>
    <div><span>🔗</span>Tap the link</div>
    <div><span>⬇️</span>Install</div>
  </div>
</body></html>
"""


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("url", help="Public https URL of the deployed download landing page")
    ap.add_argument("--out", default=str(ROOT / "qr_output"), help="Output directory")
    args = ap.parse_args()
    try:
        url = validate(args.url)
    except ValueError as e:
        sys.exit(f"✖ {e}")

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    img = make_qr(url)
    png = out / "family_food_assistant_qr.png"
    img.save(png)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    (out / "qr_print.html").write_text(PRINT_HTML.format(b64=base64.b64encode(buf.getvalue()).decode(), url=url), encoding="utf-8")
    print(f"✔ QR code: {png}\n✔ Printable page: {out / 'qr_print.html'}\n  → points to {url}")


if __name__ == "__main__":
    main()
