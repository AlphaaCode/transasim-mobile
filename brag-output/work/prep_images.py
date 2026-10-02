"""Image prep for the Sabily brag: crisp logo, wordmark, globe texture."""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
COMP = os.path.join(REPO, "brag-output", "composition", "assets")


def crisp_upscale(path_in, scale=8, blur=5.0, soft=1.4):
    """Flat white-on-transparent art -> smooth, sharp edges at `scale`x.

    The low-res alpha is treated like a distance field: upscale, blur a little,
    then re-threshold at 0.5 with a ~1.5 px smoothstep so curves stay round.
    """
    im = Image.open(path_in).convert("RGBA")
    a = im.getchannel("A")
    big = a.resize((im.width * scale, im.height * scale), Image.LANCZOS)
    big = big.filter(ImageFilter.GaussianBlur(blur))
    x = np.asarray(big).astype(np.float32) / 255.0
    # slope so the 0->1 ramp spans ~2*soft px; blur radius sets the field width
    k = blur / soft
    y = np.clip((x - 0.5) * k + 0.5, 0, 1)
    y = y * y * (3 - 2 * y)  # smoothstep
    alpha = Image.fromarray((y * 255).astype(np.uint8))
    out = Image.new("RGBA", big.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    return out.crop(out.getbbox())


def logo():
    full = crisp_upscale(os.path.join(COMP, "img", "logo-full.png"))
    full.save(os.path.join(COMP, "img", "logo-full-hi.png"))
    # the wordmark is everything below the mark: find the widest empty row band
    a = np.asarray(full.getchannel("A")) > 20
    rows = a.any(axis=1)
    h = len(rows)
    # the gap between mark and text: first empty run after the mark's top
    start = int(h * 0.3)
    gap = next(i for i in range(start, h) if not rows[i])
    text_top = next(i for i in range(gap, h) if rows[i])
    word = full.crop((0, text_top, full.width, h))
    word = word.crop(word.getbbox())
    word.save(os.path.join(COMP, "img", "wordmark-hi.png"))
    mark = full.crop((0, 0, full.width, gap))
    mark = mark.crop(mark.getbbox())
    mark.save(os.path.join(COMP, "img", "mark-outline-hi.png"))
    print("logo", full.size, "wordmark", word.size, "mark", mark.size)


# ── globe texture: the app's globe pack art, equirectangular ─────────────
# Colours from lib/core/art/pack_art_painter.dart for Sabily (primary #003c3a):
#   land (uncovered)  white @ 0.30 over the sphere
#   covered countries mix(primary, white, .86) = #DBE2E1, border mix(primary, black, .1) = #003634
#   graticule every 10 deg, white @ 0.25
POPULAR = ["SAU", "TUR", "ARE", "EGY", "MAR", "GBR", "FRA", "DZA"]


def unwrap(ring):
    out = []
    prev = None
    off = 0.0
    for lon, lat in ring:
        if prev is not None:
            d = lon + off - prev
            if d > 180:
                off -= 360
            elif d < -180:
                off += 360
        out.append((lon + off, lat))
        prev = lon + off
    return out


def rings_of(geom):
    if geom["type"] == "Polygon":
        return geom["coordinates"]
    if geom["type"] == "MultiPolygon":
        return [r for poly in geom["coordinates"] for r in poly]
    return []


def globe_texture(W=4096, SS=2):
    geo = json.load(open(os.path.join(REPO, "assets", "pack_art", "geo.json"), encoding="utf-8"))
    w, h = W * SS, W * SS // 2

    def xy(lon, lat):
        return ((lon + 180.0) / 360.0 * w, (90.0 - lat) / 180.0 * h)

    # ocean base is the sphere colour; lighting in three.js does the gradient
    base = (41, 91, 89)  # mix(primary, white, .16), the painter's globeA
    img = Image.new("RGB", (w, h), base)

    land = Image.new("L", (w, h), 0)
    dl = ImageDraw.Draw(land)
    cov = Image.new("L", (w, h), 0)
    dc = ImageDraw.Draw(cov)

    def draw_rings(draw, rings, fill):
        for ring in rings:
            pts = unwrap(ring)
            for shift in (-360, 0, 360):
                poly = [xy(lon + shift, lat) for lon, lat in pts]
                if len(poly) >= 3:
                    draw.polygon(poly, fill=fill)

    for code, c in geo["countries"].items():
        draw_rings(dc if code in POPULAR else dl, rings_of(c["g"]), 255)
    for o in geo["others"]:
        draw_rings(dl, rings_of(o), 255)

    # white land @ .30
    white = Image.new("RGB", (w, h), (255, 255, 255))
    img = Image.composite(white, img, land.point(lambda v: int(v * 0.30)))

    # covered: border ring first (dilate), then fill
    border_mask = cov.filter(ImageFilter.MaxFilter(5))
    img = Image.composite(Image.new("RGB", (w, h), (0, 54, 52)), img, border_mask)
    img = Image.composite(Image.new("RGB", (w, h), (219, 226, 225)), img, cov)

    # graticule
    grat = Image.new("L", (w, h), 0)
    dg = ImageDraw.Draw(grat)
    lw = max(1, int(1.6 * SS))
    for lon in range(-180, 181, 10):
        x, _ = xy(lon, 0)
        dg.line([(x, xy(0, 80)[1]), (x, xy(0, -80)[1])], fill=255, width=lw)
    for lat in range(-80, 81, 10):
        _, y = xy(0, lat)
        dg.line([(0, y), (w, y)], fill=255, width=lw)
    img = Image.composite(white, img, grat.point(lambda v: int(v * 0.22)))

    img = img.resize((W, W // 2), Image.LANCZOS)
    img.save(os.path.join(COMP, "img", "globe-texture.jpg"), quality=92)

    # pin anchor data for the page: centre lon/lat of each popular country
    pins = {code: geo["countries"][code]["c"] for code in POPULAR}
    json.dump(pins, open(os.path.join(COMP, "img", "pins.json"), "w"), indent=1)
    print("globe", img.size, pins)


if __name__ == "__main__":
    logo()
    globe_texture()
