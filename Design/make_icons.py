#!/usr/bin/env python3
"""
Loom icon system — generator.

Every mark on the canvas is a plot of a stated equation. Nothing is drawn
freehand. See Design/README.md for the design system this encodes.

Outputs (Design/Icons/):
    <name>.svg            default  — dark indigo ground, full colour, squircle-masked
    <name>-light.svg      light    — linen ground
    <name>-mono.svg       mono     — white-on-black, for Icon Composer Clear/Tinted
    layers/<name>-{bg,mid,fg}.svg  unmasked depth layers for Icon Composer
    icons.json            manifest consumed by build_deck.py

stdlib only. Run: python3 Design/make_icons.py
"""

import json
import math
import os

# ── Grid ─────────────────────────────────────────────────────────────────────
# Canvas is Apple's 1024 icon square. Every keyline below is derived from it by
# a power of phi, so the whole system has one number in it.
C = 1024
HALF = C / 2
PHI = (1 + 5 ** 0.5) / 2
M = round(C / PHI ** 5)          # 92   margin  — content keeps clear of the mask
LIVE = C - 2 * M                 # 840  live area
KR = LIVE / 2                    # 420  keyline circle radius
U = C // 64                      # 16   base unit; stroke weights are multiples

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Icons")
LAYERS = os.path.join(OUT, "layers")

# ── Palette ──────────────────────────────────────────────────────────────────
# Warp = the fixed threads = the platform (cool).
# Weft = the shuttle = your script (warm).
# One rule, every icon: cool structure, warm action.
THEMES = {
    "dark": dict(
        bg0="#3A2C93", bg1="#100C2E", ground="#100C2E",
        warp="#8B7BFF", warp2="#5A4FC4", weft="#FFB43D", weft2="#FF6A5A",
        glow="#FFF3E0", cyan="#3FE0E8", halo="url(#BG)", flat=False,
    ),
    "light": dict(
        bg0="#FDFAF3", bg1="#EBE0CD", ground="#F3EADA",
        warp="#4A38C4", warp2="#B9AEEA", weft="#CE6A11", weft2="#C43C22",
        glow="#1B1540", cyan="#0B7F8C", halo="url(#BG)", flat=False,
    ),
    "mono": dict(
        bg0="#000000", bg1="#000000", ground="#000000",
        warp="#B0B0B0", warp2="#6E6E6E", weft="#FFFFFF", weft2="#DADADA",
        glow="#FFFFFF", cyan="#9A9A9A", halo="#000000", flat=True,
    ),
}


# ── Path helpers ─────────────────────────────────────────────────────────────
def n(v):
    """Trim float noise out of path data."""
    r = round(v, 1)
    return int(r) if r == int(r) else r


def poly(pts, close=False):
    if not pts:
        return ""
    d = ["M%s,%s" % (n(pts[0][0]), n(pts[0][1]))]
    d += ["L%s,%s" % (n(x), n(y)) for x, y in pts[1:]]
    if close:
        d.append("Z")
    return "".join(d)


def smooth(pts, close=False):
    """Catmull-Rom through pts, emitted as cubic beziers."""
    m = len(pts)
    if m < 3:
        return poly(pts, close)

    def at(i):
        return pts[i % m] if close else pts[max(0, min(m - 1, i))]

    d = ["M%s,%s" % (n(pts[0][0]), n(pts[0][1]))]
    for i in range(m if close else m - 1):
        p0, p1, p2, p3 = at(i - 1), at(i), at(i + 1), at(i + 2)
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d.append("C%s,%s %s,%s %s,%s" % (n(c1[0]), n(c1[1]), n(c2[0]), n(c2[1]),
                                         n(p2[0]), n(p2[1])))
    if close:
        d.append("Z")
    return "".join(d)


def squircle(size=C, exponent=5.0, samples=56):
    """|2x/s|^k + |2y/s|^k = 1 — the Lame curve Apple's icon mask approximates
    (k≈5.2 measured; k=5 is within 0.1% of the shipping template)."""
    a = size / 2
    pts = []
    for i in range(samples):
        th = 2 * math.pi * i / samples
        cs, sn = math.cos(th), math.sin(th)
        pts.append((a + a * math.copysign(abs(cs) ** (2 / exponent), cs),
                    a + a * math.copysign(abs(sn) ** (2 / exponent), sn)))
    return smooth(pts, close=True)


SQUIRCLE = squircle()


def stroke(d, color, w, cap="round", join="round", opacity=None, dash=None):
    o = ' opacity="%s"' % opacity if opacity is not None else ""
    s = ' stroke-dasharray="%s"' % dash if dash else ""
    return ('<path d="%s" fill="none" stroke="%s" stroke-width="%s" '
            'stroke-linecap="%s" stroke-linejoin="%s"%s%s/>'
            % (d, color, n(w), cap, join, o, s))


def rect(x, y, w, h, fill, rx=0, opacity=None, sc=None, sw=0):
    r = ' rx="%s"' % n(rx) if rx else ""
    o = ' opacity="%s"' % opacity if opacity is not None else ""
    s = ' stroke="%s" stroke-width="%s"' % (sc, n(sw)) if sc else ""
    return '<rect x="%s" y="%s" width="%s" height="%s"%s fill="%s"%s%s/>' % (
        n(x), n(y), n(w), n(h), r, fill, s, o)


def circle(cx, cy, r, fill=None, sc=None, sw=0, opacity=None):
    f = ' fill="%s"' % fill if fill else ' fill="none"'
    s = ' stroke="%s" stroke-width="%s"' % (sc, n(sw)) if sc else ""
    o = ' opacity="%s"' % opacity if opacity is not None else ""
    return '<circle cx="%s" cy="%s" r="%s"%s%s%s/>' % (n(cx), n(cy), n(r), f, s, o)


def lerp_hex(a, b, t):
    a, b = a.lstrip("#"), b.lstrip("#")
    v = [int(round(int(a[i:i + 2], 16) + (int(b[i:i + 2], 16) - int(a[i:i + 2], 16)) * t))
         for i in (0, 2, 4)]
    return "#%02X%02X%02X" % tuple(max(0, min(255, x)) for x in v)


def marching_squares(fn, res=64, level=0.0):
    """Zero-contour of fn over the unit square, as segments in canvas space."""
    grid = [[fn(i / res, j / res) - level for j in range(res + 1)]
            for i in range(res + 1)]
    segs = []
    for i in range(res):
        for j in range(res):
            p = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
            v = [grid[a][b] for a, b in p]
            if all(x > 0 for x in v) or all(x <= 0 for x in v):
                continue
            xs = []
            for e in range(4):
                a, b = e, (e + 1) % 4
                if (v[a] > 0) != (v[b] > 0):
                    t = v[a] / (v[a] - v[b])
                    xs.append((p[a][0] + (p[b][0] - p[a][0]) * t,
                               p[a][1] + (p[b][1] - p[a][1]) * t))
            for k in range(0, len(xs) - 1, 2):
                segs.append((xs[k], xs[k + 1]))
    sc = LIVE / res
    return [((M + a[0] * sc, M + a[1] * sc), (M + b[0] * sc, M + b[1] * sc))
            for a, b in segs]


# ── Icon builders ────────────────────────────────────────────────────────────
# Each returns (mid, fg): two lists of svg fragments. `mid` is structure, `fg`
# is the hero mark. The ground is added by the wrapper. That split is exactly
# the background / mid-ground / foreground stack Icon Composer wants.

def ic_plain_weave(t):
    """Parity interlace. Warp passes over weft where (i+j) is even."""
    w, g = 180, 150
    p = [M + k * (w + g) for k in range(3)]                        # span = LIVE exactly
    mid = [rect(x, -24, w, C + 48, t["warp"]) for x in p]          # warp, full bleed
    fg = [rect(-24, y, C + 48, w, t["weft"]) for y in p]           # weft over everything
    for i, x in enumerate(p):                                       # warp back on top
        for j, y in enumerate(p):
            if (i + j) % 2 == 0:
                fg.append(rect(x, y - 2, w, w + 4, t["warp"]))     # +2 kills the seam
    return mid, fg


def ic_shuttle(t):
    """y = A sin(2pi(x-x0)/L). Rails sit on the zeros, so the ribbon meets each
    one at a crossing and passes alternately over and under."""
    L, A, x0 = 512, 230, 128
    rails = [x0 + k * L / 2 for k in range(4)]
    mid = [rect(x - 28, -24, 56, C + 48, t["warp2"]) for x in rails]
    pts = [(x, HALF + A * math.sin(2 * math.pi * (x - x0) / L))
           for x in range(-40, 1065, 4)]
    fg = [stroke(poly(pts), t["weft"], 108)]
    for k, x in enumerate(rails):                                   # odd rails on top
        if k % 2:
            fg.append(rect(x - 28, HALF - 300, 56, 600, t["warp2"]))
    return mid, fg


def ic_braid(t):
    """Three strands, y_i = A sin(2pi x/L + 2pi i/3); depth z_i = cos(same).
    Painter order is the sort of z, so the plait is exact rather than drawn."""
    L, A, sw = 512, 152, 92
    cols = [t["warp"], t["cyan"], t["weft"]]
    ph = [2 * math.pi * i / 3 for i in range(3)]

    def y(i, x):
        return HALF + A * math.sin(2 * math.pi * x / L + ph[i])

    def z(i, x):
        return math.cos(2 * math.pi * x / L + ph[i])

    xs = list(range(-48, 1073, 4))
    bounds, order = [0], tuple(sorted(range(3), key=lambda i: z(i, xs[0])))
    orders = [order]
    for k, x in enumerate(xs[1:], 1):
        o = tuple(sorted(range(3), key=lambda i: z(i, x)))
        if o != order:
            bounds.append(k)
            orders.append(o)
            order = o
    bounds.append(len(xs))
    # runs overlap by 6 samples so no halo bites the neighbour's stroke; the
    # order only flips where the swapping pair is far apart in y, so it is safe
    runs = [(orders[i], xs[max(0, bounds[i] - 10):min(len(xs), bounds[i + 1] + 10)])
            for i in range(len(orders))]

    fg = []
    for o, sx in runs:
        for i in o:                                                 # low z first
            d = poly([(x, y(i, x)) for x in sx])
            fg.append(stroke(d, t["halo"], sw + 34, cap="butt"))
            fg.append(stroke(d, cols[i], sw, cap="butt"))
    return [], fg


def ic_twill(t):
    """A 2/2 twill draft — the binary matrix a Jacquard card punches.
    Filled where (i+j) mod 4 < 2."""
    k = 8
    cell = LIVE / k
    pad, r = 15, 22
    mid = [rect(M - 18, M - 18, LIVE + 36, LIVE + 36, t["warp2"], 46)]   # the card
    fg = [rect(M + i * cell + pad, M + j * cell + pad,
               cell - 2 * pad, cell - 2 * pad, t["weft"], r)             # the holes
          for i in range(k) for j in range(k) if (j - i) % 4 < 2]
    return mid, fg


def ic_standing_wave(t):
    """y = A sin(kx) cos(wt), sampled at five phases. Nodes are fixed; the
    antinodes breathe between the envelope pair."""
    A, k, x0 = 300, math.pi / 280, M
    xs = [x for x in range(M - 20, C - M + 21, 4)]

    def curve(a):
        return poly([(x, HALF - A * a * math.sin(k * (x - x0))) for x in xs])

    mid = [stroke(poly([(M - 20, HALF), (C - M + 20, HALF)]), t["warp2"], 16),
           stroke(curve(0.62), t["warp"], 30),
           stroke(curve(-0.62), t["warp"], 30)]
    fg = [stroke(curve(1), t["weft"], 52), stroke(curve(-1), t["weft"], 52)]
    fg += [circle(x0 + i * 280, HALF, 26, t["glow"]) for i in range(4)]
    return mid, fg


def ic_beat(t):
    """sin(2pi*3u) + sin(2pi*5u) = 2 cos(2 pi u) sin(8 pi u).
    Two near frequencies; the envelope is the thing you didn't write."""
    A = 310
    xs = [x for x in range(M - 20, C - M + 21, 3)]

    def u(x):
        return (x - M) / LIVE

    env = [(x, A * abs(math.cos(2 * math.pi * u(x)))) for x in xs]
    mid = [stroke(poly([(x, HALF - e) for x, e in env]), t["warp2"], 16, dash="32 26", opacity=0.75),
           stroke(poly([(x, HALF + e) for x, e in env]), t["warp2"], 16, dash="32 26", opacity=0.75)]
    fg = [stroke(poly([(x, HALF - e * math.sin(8 * math.pi * u(x)))
                       for x, e in env]), t["weft"], 46)]
    return mid, fg


def ic_packet(t):
    """A e^(-(x-c)^2 / 2s^2) cos(k(x-c)) — one bounded event in an unbounded
    medium. The shape of a single run."""
    A, s, k = 330, 178, 2 * math.pi / 196
    xs = [x for x in range(M - 30, C - M + 31, 3)]

    def gauss(x):
        return math.exp(-((x - HALF) ** 2) / (2 * s * s))

    mid = [stroke(poly([(x, HALF - A * gauss(x)) for x in xs]), t["warp2"], 14, dash="30 24"),
           stroke(poly([(x, HALF + A * gauss(x)) for x in xs]), t["warp2"], 14, dash="30 24")]
    fg = [stroke(poly([(x, HALF - A * gauss(x) * math.cos(k * (x - HALF))) for x in xs]),
                 t["weft"], 48)]
    return mid, fg


def ic_fourier(t):
    """S_N(u) = 4/pi * sum_{n odd <= N} sin(2 pi n u)/n. Four partial sums,
    converging on a square wave. Composition, drawn."""
    A = 296
    xs = [x for x in range(M - 16, C - M + 17, 2)]

    def s(N, x):
        u = (x - M) / LIVE
        return (4 / math.pi) * sum(math.sin(2 * math.pi * i * u) / i
                                   for i in range(1, N + 1, 2))

    layers = [(1, t["warp2"], 20), (5, t["warp"], 26), (31, t["weft"], 42)]
    out = [stroke(poly([(x, HALF - A * s(N, x)) for x in xs]), c, w)
           for N, c, w in layers]
    return out[:2], out[2:]


def ic_moire(t):
    """Two parallel gratings of pitch d1, d2. Beat pitch
    L = d1 d2 / |d2 - d1| = 46*54/8 = 310 — four times either grating, and
    nothing in the file is drawn at that size."""
    R = 404
    mid = [circle(HALF, HALF, R, t["halo"])]
    fg = []
    # Same colour and opacity in both gratings — the fringes have to come from
    # coincidence, not from tinting. Where lines land together the disc reads
    # open; where they interleave it reads solid.
    for d in (46, 54):
        g = "".join(
            stroke(poly([(HALF + i * d, HALF - 440), (HALF + i * d, HALF + 440)]),
                   t["weft"], 13, cap="butt")
            for i in range(-int(R / d) - 1, int(R / d) + 2))
        fg.append('<g clip-path="url(#DISC)">%s</g>' % g)
    fg.append(circle(HALF, HALF, R, sc=t["warp"], sw=20))
    return mid, fg


def ic_two_source(t):
    """Circular wavefronts r = n*lambda from two sources 2a apart. The
    hyperbolae between them are where the two agree."""
    lam, a = 78, 172
    mid, fg = [], []
    for k, (cx, col) in enumerate(((HALF - a, t["warp"]), (HALF + a, t["weft"]))):
        for i in range(1, 8):
            (mid if k == 0 else fg).append(
                circle(cx, HALF, i * lam, sc=col, sw=20, opacity=0.9))
    fg += [circle(HALF - a, HALF, 30, t["warp"]), circle(HALF + a, HALF, 30, t["weft"])]
    return mid, fg


def ic_chladni(t):
    """Nodal set of the (2,5) square-plate mode:
    cos(2 pi x) cos(5 pi y) - cos(5 pi x) cos(2 pi y) = 0.
    Where a vibrating plate stays still, sand collects."""
    p, q = 2, 5

    def f(x, y):
        return (math.cos(p * math.pi * x) * math.cos(q * math.pi * y)
                - math.cos(q * math.pi * x) * math.cos(p * math.pi * y))

    segs = marching_squares(f, res=88)
    d = "".join("M%s,%s L%s,%s" % (n(a[0]), n(a[1]), n(b[0]), n(b[1])) for a, b in segs)
    mid = [rect(M, M, LIVE, LIVE, "none", rx=28, sc=t["warp2"], sw=14, opacity=0.8)]
    return mid, [stroke(d, t["weft"], 26)]


def ic_lissajous(t):
    """x = cos 3t, y = sin 2t. A 3:2 frequency ratio closes; anything
    irrational never does."""
    R = 388
    pts = [(HALF + R * math.cos(3 * i * 2 * math.pi / 720),
            HALF + R * math.sin(2 * i * 2 * math.pi / 720)) for i in range(721)]
    grad = t["weft"] if t["flat"] else "url(#GRAD)"
    mid = [circle(HALF, HALF, KR, sc=t["warp2"], sw=10, opacity=0.6)]
    return mid, [stroke(poly(pts), grad, 78)]


def ic_harmonograph(t):
    """Two damped pendulums per axis:
    x = sum A e^(-d t) sin(f t + p). Detuning f by 0.005 is what makes it
    drift instead of repeat."""
    A, T = 402.0, 42.0
    d = 0.8 / T                                   # amplitude falls to e^-0.8 over the run
    fx, fy = 2 + 2 * math.pi / T, 3.0             # detune so the figure precesses once
    pts, tt = [], 0.0
    while tt <= T:
        e = A * math.exp(-d * tt)
        pts.append((HALF + e * math.sin(fx * tt + math.pi / 4),
                    HALF + e * math.sin(fy * tt)))
        tt += T / 2400
    return [], [stroke(poly(pts), t["weft"], 13)]


def ic_trefoil(t):
    """(2,3) torus knot: x = sin t + 2 sin 2t, y = cos t - 2 cos 2t,
    z = -sin 3t. z is exact, so every crossing is decided by the equation."""
    s, sw = 132.0, 84
    def P(tt):
        return (HALF + s * (math.sin(tt) + 2 * math.sin(2 * tt)),
                HALF + s * (math.cos(tt) - 2 * math.cos(2 * tt)),
                -math.sin(3 * tt))

    arcs = []                                                       # split at z = 0
    for a in range(6):
        t0, t1 = a * math.pi / 3, (a + 1) * math.pi / 3
        step = (t1 - t0) / 48
        # run 3 samples past each end: a butt-capped halo cuts a notch out of the
        # neighbouring arc on the outside of a curve, and the overlap paints it back
        pts = [P(t0 + (i - 3) * step) for i in range(55)]
        mean = sum(P(t0 + (t1 - t0) * i / 48)[2] for i in range(49)) / 49
        arcs.append((mean, [(p[0], p[1]) for p in pts]))
    arcs.sort(key=lambda a: a[0])

    fg = []
    for _, pts in arcs:
        d = poly(pts)
        fg.append(stroke(d, t["halo"], sw + 40, cap="butt"))
        fg.append(stroke(d, t["weft"], sw, cap="butt"))
        fg.append(stroke(d, t["warp"], 20, cap="butt"))              # the plied core
    return [], fg


def ic_rosette(t):
    """Hypotrochoid, R=5 r=3 d=5:
    x = 2 cos th + 5 cos(2 th/3), y = 2 sin th - 5 sin(2 th/3)."""
    R, r, dd = 8.0, 3.0, 7.0
    k = (R - r) / r

    def curve(scale, rot=0.0):
        pts = []
        for i in range(1081):
            th = i * 6 * math.pi / 1080
            x = (R - r) * math.cos(th) + dd * math.cos(k * th)
            y = (R - r) * math.sin(th) - dd * math.sin(k * th)
            cr, sr = math.cos(rot), math.sin(rot)
            pts.append((HALF + scale * (x * cr - y * sr), HALF + scale * (x * sr + y * cr)))
        return poly(pts)

    sc = KR / (R - r + dd)
    grad = t["weft"] if t["flat"] else "url(#GRAD)"
    mid = [stroke(curve(sc * 0.99, math.pi / 8), t["warp2"], 13, opacity=0.55)]
    return mid, [stroke(curve(sc), grad, 32)]


def ic_loop(t):
    """Lemniscate of Bernoulli, x = a cos t/(1+sin^2 t), turned 45 degrees.
    One curve, two lobes, one crossing — woven at the centre."""
    a, sw = 470.0, 94
    rot = math.pi / 4
    cr, sr = math.cos(rot), math.sin(rot)

    def lobe(t0, t1):
        pts = []
        for i in range(241):
            tt = t0 + (t1 - t0) * i / 240
            den = 1 + math.sin(tt) ** 2
            x, y = a * math.cos(tt) / den, a * math.sin(tt) * math.cos(tt) / den
            pts.append((HALF + x * cr - y * sr, HALF + x * sr + y * cr))
        return poly(pts)

    lo = lobe(-math.pi / 2, math.pi / 2)
    hi = lobe(math.pi / 2, 3 * math.pi / 2)
    return [stroke(lo, t["warp"], sw)], [
        stroke(hi, t["halo"], sw + 40), stroke(hi, t["weft"], sw)]


def ic_phyllotaxis(t):
    """Vogel's model: theta = n * 137.507 deg, r = c sqrt(n). The golden angle
    is the only one that never lets a row line up."""
    N, c = 232, 26.6
    ga = math.radians(137.50776405)
    mid, fg = [], []
    for i in range(1, N + 1):
        th, r = i * ga, c * math.sqrt(i)
        x, y = HALF + r * math.cos(th), HALF + r * math.sin(th)
        u = i / N
        col = t["weft"] if t["flat"] and u > 0.5 else (
            t["warp"] if t["flat"] else lerp_hex(t["warp"], t["weft"], u ** 0.85))
        (fg if u > 0.45 else mid).append(circle(x, y, 7 + 15 * u ** 0.7, col))
    return mid, fg


def ic_serpentine(t):
    """Boustrophedon — the shuttle's path, turning at each selvedge.
    Straight runs joined by semicircles of radius = half the row pitch."""
    pitch, r = 224, 112
    y0 = HALF - pitch
    mid = [rect(x - 13, -24, 26, C + 48, t["warp2"])
           for x in (M + 40, M + 240, HALF, C - M - 240, C - M - 40)]
    d = ("M-48,%s H820 A%s,%s 0 0 1 820,%s H204 A%s,%s 0 0 0 204,%s H1072"
         % (n(y0), r, r, n(y0 + pitch), r, r, n(y0 + 2 * pitch)))
    grad = t["weft"] if t["flat"] else "url(#GRAD)"
    return mid, [stroke(d, grad, 98, cap="butt")]


# ── Catalogue ────────────────────────────────────────────────────────────────
ICONS = [
    ("plain-weave", "Weave", "Plain Weave", ic_plain_weave,
     "over(i,j) = (i + j) mod 2",
     "The loom's atom. Three warp, three weft, strict parity — the only rule a plain weave has."),
    ("shuttle", "Weave", "Shuttle", ic_shuttle,
     "y = A sin(2π(x − x₀)/λ),  rails at the zeros",
     "A weft thread crossing four warp rails. Rails sit exactly on the zeros, so every meeting is a crossing."),
    ("braid", "Weave", "Braid", ic_braid,
     "yᵢ = A sin(φ + 2πi/3),  zᵢ = cos(φ + 2πi/3)",
     "Three strands, 120° apart. Depth is the cosine of the same phase, so the plait resolves itself."),
    ("twill", "Weave", "Twill Card", ic_twill,
     "punched ⇔ (j − i) mod 4 < 2",
     "A 2/2 twill draft — the diagonal of denim, and the binary matrix a Jacquard card punches. The first program was a fabric."),
    ("standing-wave", "Wave", "Standing Wave", ic_standing_wave,
     "y = A sin(kx) cos(ωt)",
     "Five phases of the same wave. The nodes never move — the fixed points a running script returns to."),
    ("beat", "Wave", "Beat", ic_beat,
     "sin(2π·3u) + sin(2π·5u) = 2 cos(2πu) sin(8πu)",
     "Two close frequencies summed. The envelope is emergent — nobody drew it."),
    ("packet", "Wave", "Packet", ic_packet,
     "y = A e^(−(x−c)²/2σ²) cos k(x−c)",
     "One bounded event in an unbounded medium. The shape of a single run."),
    ("fourier", "Wave", "Fourier", ic_fourier,
     "Sₙ(u) = (4/π) Σ sin(2πnu)/n,  n odd",
     "Partial sums converging on a square wave, Gibbs ears and all. Small honest parts, one complex whole."),
    ("moire", "Interference", "Moiré", ic_moire,
     "Λ = d₁d₂ / |d₂ − d₁| = 46·54/8",
     "Two gratings crossed at 10°. Moiré is a textile word first — watered silk. The fringes are bigger than anything drawn."),
    ("two-source", "Interference", "Two Source", ic_two_source,
     "r = nλ from each of two sources 2a apart",
     "Circular wavefronts from two points. The hyperbolae between them mark where the two agree."),
    ("chladni", "Interference", "Chladni", ic_chladni,
     "cos 2πx cos 5πy − cos 5πx cos 2πy = 0",
     "The nodal set of a vibrating square plate. Sand collects on the lines that stay still."),
    ("lissajous", "Orbit", "Lissajous", ic_lissajous,
     "x = cos 3t,  y = sin 2t",
     "A 3:2 ratio closes into a knot. Make the ratio irrational and it never returns."),
    ("harmonograph", "Orbit", "Harmonograph", ic_harmonograph,
     "x = Σ A e^(−dt) sin(ft + p)",
     "Four damped pendulums, detuned by 0.005. A Victorian drawing machine — automation before electricity."),
    ("trefoil", "Orbit", "Trefoil", ic_trefoil,
     "(2,3) torus knot,  z = −sin 3t",
     "The simplest knot that cannot be undone. Every crossing is decided by z, not by hand. Drawn as plied yarn."),
    ("rosette", "Orbit", "Rosette", ic_rosette,
     "x = 5 cos θ + 7 cos(5θ/3)",
     "A hypotrochoid — the spirograph. Three turns to close, with a second copy off by 30° for depth."),
    ("loop", "Orbit", "Loop", ic_loop,
     "ρ² = a² cos 2θ,  rotated 45°",
     "Lemniscate of Bernoulli. One curve, two lobes, one crossing — and the crossing is woven."),
    ("phyllotaxis", "Order", "Phyllotaxis", ic_phyllotaxis,
     "θ = n · 137.507°,  r = c√n",
     "The golden angle: the one divergence that never lets a row line up. 232 points, no collisions."),
    ("serpentine", "Order", "Serpentine", ic_serpentine,
     "boustrophedon,  turn radius = pitch/2",
     "As the ox ploughs. The shuttle's path across the warp, turning at each selvedge."),
]

FAMILIES = {
    "Weave": "The literal loom. Warp, weft, and the over-under rule that makes cloth out of thread.",
    "Wave": "A thread is also a signal. These are the shapes a running script makes.",
    "Interference": "Two simple things overlaid produce a third nobody specified. Automation's whole promise.",
    "Orbit": "Closed paths. Loops that return, knots that hold.",
    "Order": "The grid underneath. Packing, sequence, and the path the machine takes.",
}


# ── Assembly ─────────────────────────────────────────────────────────────────
def build(slug, fn, variant):
    t = THEMES[variant]
    uid = "%s-%s" % (slug, variant)
    mid, fg = fn(t)

    defs = ['<clipPath id="M"><path d="%s"/></clipPath>' % SQUIRCLE,
            '<clipPath id="DISC"><circle cx="512" cy="512" r="404"/></clipPath>']
    if t["flat"]:
        ground = rect(0, 0, C, C, t["ground"])
    else:
        defs.append('<linearGradient id="BG" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="358" y2="1024">'
                    '<stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/>'
                    '</linearGradient>' % (t["bg0"], t["bg1"]))
        defs.append('<linearGradient id="GRAD" x1="0.05" y1="0.05" x2="0.95" y2="0.95">'
                    '<stop offset="0" stop-color="%s"/><stop offset="0.42" stop-color="%s"/>'
                    '<stop offset="0.78" stop-color="%s"/><stop offset="1" stop-color="%s"/>'
                    '</linearGradient>'
                    % (t["warp"], t["warp"], t["weft2"], t["weft"]))
        ground = rect(0, 0, C, C, "url(#BG)")

    body = ('<g clip-path="url(#M)">%s<g>%s</g><g>%s</g></g>'
            % (ground, "".join(mid), "".join(fg)))
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" '
           'height="%d"><defs>%s</defs>%s</svg>' % (C, C, C, C, "".join(defs), body))
    # namespace ids so many icons can be inlined on one page
    for i in ("M", "DISC", "BG", "GRAD"):
        svg = svg.replace('id="%s"' % i, 'id="%s-%s"' % (uid, i))
        svg = svg.replace('url(#%s)' % i, 'url(#%s-%s)' % (uid, i))
    return svg


def build_layer(slug, fn, which):
    """Unmasked, transparent-ground layer for Icon Composer."""
    t = THEMES["dark"]
    mid, fg = fn(t)
    uid = "%s-%s" % (slug, which)
    defs = ['<clipPath id="DISC"><circle cx="512" cy="512" r="404"/></clipPath>',
            '<linearGradient id="BG" gradientUnits="userSpaceOnUse" x1="0" y1="0" '
            'x2="358" y2="1024"><stop offset="0" stop-color="%s"/>'
            '<stop offset="1" stop-color="%s"/></linearGradient>' % (t["bg0"], t["bg1"]),
            '<linearGradient id="GRAD" x1="0.05" y1="0.1" x2="0.95" y2="0.9">'
            '<stop offset="0" stop-color="%s"/><stop offset="0.55" stop-color="%s"/>'
            '<stop offset="1" stop-color="%s"/></linearGradient>'
            % (t["warp"], t["weft2"], t["weft"])]
    if which == "bg":
        body = rect(0, 0, C, C, "url(#BG)")
    else:
        body = "".join(mid if which == "mid" else fg)
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" '
           'height="%d"><defs>%s</defs>%s</svg>' % (C, C, C, C, "".join(defs), body))
    for i in ("DISC", "BG", "GRAD"):
        svg = svg.replace('id="%s"' % i, 'id="%s-%s"' % (uid, i))
        svg = svg.replace('url(#%s)' % i, 'url(#%s-%s)' % (uid, i))
    return svg


def main():
    os.makedirs(LAYERS, exist_ok=True)
    manifest = []
    for slug, family, title, fn, eq, note in ICONS:
        variants = {v: build(slug, fn, v) for v in ("dark", "light", "mono")}
        open(os.path.join(OUT, "%s.svg" % slug), "w").write(variants["dark"])
        open(os.path.join(OUT, "%s-light.svg" % slug), "w").write(variants["light"])
        open(os.path.join(OUT, "%s-mono.svg" % slug), "w").write(variants["mono"])
        for which in ("bg", "mid", "fg"):
            open(os.path.join(LAYERS, "%s-%s.svg" % (slug, which)), "w").write(
                build_layer(slug, fn, which))
        manifest.append(dict(slug=slug, family=family, title=title, eq=eq, note=note,
                             doc=(fn.__doc__ or "").strip(), **variants))
        print("  %-14s %6.1f KB" % (slug, len(variants["dark"]) / 1024))

    payload = dict(
        grid=dict(canvas=C, margin=M, live=LIVE, keyline=KR, unit=U, phi=round(PHI, 6)),
        palette={k: v for k, v in THEMES.items()},
        families=FAMILIES,
        icons=manifest,
    )
    open(os.path.join(OUT, "icons.json"), "w").write(json.dumps(payload, separators=(",", ":")))
    print("\n%d icons x 3 variants + 3 layers each -> %s" % (len(ICONS), OUT))


if __name__ == "__main__":
    main()
