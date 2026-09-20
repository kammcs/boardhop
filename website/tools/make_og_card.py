#!/usr/bin/env python3
"""Render the social share card from tools/og-card.html.

    python website/tools/make_og_card.py

Writes img/brand/og-card.png at 1200x630 -- the size every unfurler crops
toward -- and img/brand/og-card-square.png at 1200x1200 for the clients that
prefer a square.

PNG, not WebP: WebP is the weakest format for link previews. Apple's iMessage
preview is unreliable with it and Facebook and LinkedIn have historically
declined it outright. The card is flat colour over a photograph-free layout,
so PNG stays small anyway.

Needs Playwright with the system Chrome channel, and a local web server for
the page's own assets:

    cd website && python -m http.server 4173 --bind 127.0.0.1
"""

import os
import sys

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
SITE = os.path.dirname(HERE)
OUT = os.path.join(SITE, "img", "brand")
BASE = os.environ.get("SITE_BASE", "http://127.0.0.1:4173")

CARDS = [
    ("og-card.png", 1200, 630),
    ("og-card-square.png", 1200, 1200),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="chrome")
        for name, w, h in CARDS:
            page = browser.new_page(
                viewport={"width": w, "height": h}, device_scale_factor=1
            )
            page.goto(f"{BASE}/tools/og-card.html", wait_until="networkidle")
            # The card is sized in CSS for 1200x630; the square crop just gives
            # it more height to breathe in.
            page.add_style_tag(
                content=f"html,body,.card{{width:{w}px;height:{h}px}}"
            )
            # Web fonts load after networkidle often enough to matter here:
            # a card rendered in the fallback face is the whole point missed.
            page.evaluate("() => document.fonts.ready")
            page.wait_for_timeout(1200)
            path = os.path.join(OUT, name)
            page.screenshot(path=path)
            size = round(os.path.getsize(path) / 1024)
            print(f"{os.path.relpath(path, SITE)}  {w}x{h}  {size} KB")
            page.close()
        browser.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 - a CLI, the message is the point
        print(f"failed: {exc}", file=sys.stderr)
        print(f"is a server running at {BASE}?", file=sys.stderr)
        raise SystemExit(1)
