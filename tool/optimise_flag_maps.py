# -*- coding: utf-8 -*-
"""Shrinks the bundled flag-map SVGs without changing the flag.

    python tool/optimise_flag_maps.py

These come from Wikimedia and several are raster traces: Malaysia alone
carried 1,987 paths and 213,609 line commands, which is coastline detail three
orders of magnitude finer than the 340x132 card it is drawn on, and which
flutter_svg has to parse on every first render.

What this does, and what it deliberately does not:

  * Polygonal subpaths (M/L/H/V/Z only) are simplified with Douglas-Peucker at
    a tolerance relative to the drawing's own size, so the OUTLINE loses
    vertices a viewer could never resolve. The shape stays the shape.
  * Subpaths containing curves are left alone. A flag map's stripes and
    charges are drawn with curves, and approximating those is how you turn a
    crescent into a blob.
  * Coordinate precision is reduced and editor metadata stripped.

Nothing is deleted: every subpath that goes in comes out. The flag's design is
untouched because only vertex density changes.
"""
import io
import math
import os
import re
import sys

DIR = 'assets/flag_maps'

COMMENT = re.compile(r'<!--.*?-->', re.S)
# Matched to its OWN closing tag, with self-closing handled separately. The
# obvious `<(metadata|...)\b.*?(</\1>|/>)` is wrong: `.*?` stops at the first
# `/>` ANYWHERE after the opening tag, which is normally a self-closing child,
# so it eats the opening and orphans the real `</metadata>`. That silently
# produced 53 unparseable files before it was caught.
META = re.compile(r'<(metadata|sodipodi:namedview)\b[^>]*>.*?</\1\s*>', re.S | re.I)
META_EMPTY = re.compile(r'<(metadata|sodipodi:namedview)\b[^>]*/>', re.I)
NSATTR = re.compile(r'\s(inkscape|sodipodi|rdf|cc|dc):[\w-]+="[^"]*"')
DATTR = re.compile(r'(\sd=")([^"]*)(")')
TOKEN = re.compile(r'([MmLlHhVvZzCcSsQqTtAa])|(-?\d*\.?\d+(?:e-?\d+)?)')

# Fraction of the viewBox diagonal below which a vertex cannot matter.
TOLERANCE = 0.0006


def rdp(pts, eps):
    if len(pts) < 3:
        return pts
    ax, ay = pts[0]
    bx, by = pts[-1]
    den = math.hypot(bx - ax, by - ay)
    dmax, idx = 0.0, 0
    for i in range(1, len(pts) - 1):
        px, py = pts[i]
        d = (math.hypot(px - ax, py - ay) if den < 1e-12
             else abs((by - ay) * px - (bx - ax) * py + bx * ay - by * ax) / den)
        if d > dmax:
            dmax, idx = d, i
    if dmax > eps:
        return rdp(pts[:idx + 1], eps)[:-1] + rdp(pts[idx:], eps)
    return [pts[0], pts[-1]]


def split_subpaths(d):
    """Tokenised `d` split into (command, numbers) runs per subpath."""
    toks = [(c, n) for c, n in TOKEN.findall(d)]
    subs, cur = [], []
    for cmd, num in toks:
        if cmd:
            if cmd in 'Mm' and cur:
                subs.append(cur)
                cur = []
            cur.append([cmd, []])
        elif cur:
            cur[-1][1].append(float(num))
    if cur:
        subs.append(cur)
    return subs


def to_points(sub):
    """Absolute points for a polygonal subpath, or None if it has curves."""
    pts, x, y, closed = [], 0.0, 0.0, False
    for cmd, nums in sub:
        u = cmd.upper()
        rel = cmd.islower()
        if u in 'CSQTA':
            return None, False
        if u == 'Z':
            closed = True
            continue
        if u == 'M' or u == 'L':
            for i in range(0, len(nums) - 1, 2):
                nx, ny = nums[i], nums[i + 1]
                x, y = (x + nx, y + ny) if rel else (nx, ny)
                pts.append((x, y))
        elif u == 'H':
            for nx in nums:
                x = x + nx if rel else nx
                pts.append((x, y))
        elif u == 'V':
            for ny in nums:
                y = y + ny if rel else ny
                pts.append((x, y))
    return pts, closed


def fmt(v, dec):
    s = f'{v:.{dec}f}'.rstrip('0').rstrip('.')
    return s if s not in ('', '-0') else '0'


def emit(pts, closed, dec):
    out = [f'M{fmt(pts[0][0], dec)} {fmt(pts[0][1], dec)}']
    for x, y in pts[1:]:
        out.append(f'L{fmt(x, dec)} {fmt(y, dec)}')
    if closed:
        out.append('Z')
    return ''.join(out)


def viewbox_diagonal(svg):
    m = re.search(r'viewBox="([-\d.eE]+)[ ,]+([-\d.eE]+)[ ,]+([-\d.eE]+)[ ,]+([-\d.eE]+)"', svg)
    if m:
        w, h = abs(float(m.group(3))), abs(float(m.group(4)))
        if w and h:
            return math.hypot(w, h)
    return 1000.0


def optimise(svg, dec):
    diag = viewbox_diagonal(svg)
    eps = diag * TOLERANCE

    def one(m):
        head, d, tail = m.group(1), m.group(2), m.group(3)
        pieces = []
        for sub in split_subpaths(d):
            pts, closed = to_points(sub)
            if pts is None or len(pts) < 3:
                # Curves, or too small to simplify: re-emit verbatim.
                raw = ''.join(c + ' '.join(fmt(n, dec) for n in nums) for c, nums in sub)
                pieces.append(raw)
                continue
            pieces.append(emit(rdp(pts, eps), closed, dec))
        return head + ''.join(pieces) + tail

    svg = COMMENT.sub('', svg)
    svg = META.sub('', svg)
    svg = META_EMPTY.sub('', svg)
    svg = NSATTR.sub('', svg)
    svg = DATTR.sub(one, svg)
    return re.sub(r'>\s+<', '><', svg)


def main():
    sys.setrecursionlimit(100000)
    files = sorted(f for f in os.listdir(DIR) if f.endswith('.svg'))
    before = after = 0
    worst = []
    for f in files:
        p = os.path.join(DIR, f)
        raw = io.open(p, encoding='utf-8', errors='ignore').read()
        b = len(raw.encode('utf-8'))
        dec = 1 if b > 500_000 else 2
        out = optimise(raw, dec)
        a = len(out.encode('utf-8'))
        # Never write a file that got bigger.
        if a < b:
            io.open(p, 'w', encoding='utf-8', newline='\n').write(out)
        else:
            a = b
        before += b
        after += a
        worst.append((a, f))
    worst.sort(reverse=True)
    print('%d files  %.1f MB -> %.1f MB  (%.0f%% saved)'
          % (len(files), before / 1e6, after / 1e6, 100 * (1 - after / before)))
    print('largest now:', ', '.join('%s %.0fKB' % (f, a / 1024) for a, f in worst[:6]))


if __name__ == '__main__':
    main()
