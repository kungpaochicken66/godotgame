#!/usr/bin/env python3
"""Lantern Lane Apple TV brand art (atv-r20-controller): original layered SVG sources.

The composition and palette follow the game's own icon (game/icon.svg): the green field, the round green
hill and the golden lantern on its hook. tvOS app icons are layered (Apple: 2 to 5 layers; the back layer
opaque, the others transparent) so the system can add its parallax; the Top Shelf images are wide scenes.
Everything is drawn here from basic shapes, no third-party art. Run, then rasterize.gd renders the PNGs:

  python3 tv/brand/make_brand.py
  scripts/godot.sh --headless --path game -s res://../tv/brand/rasterize.gd   (see README.md)
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent
# game/icon.svg palette
FIELD, FIELD_DARK, HILL, HILL_DARK = '#557c5e', '#456a4d', '#a9d27f', '#8fbe68'
CAP, BODY, GLOW, CREAM = '#edcf81', '#f2cf6b', '#fff4c9', '#fffdf6'


def svg(w, h, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>\n'


def lantern(cx, top, s):
    """The game icon's lantern (icon.svg, 256 px) scaled by s, its hook starting at (cx, top)."""
    def r(x, y, w, h, rx, fill):
        return f'<rect x="{cx + (x - 128) * s:.1f}" y="{top + (y - 52) * s:.1f}" width="{w * s:.1f}" height="{h * s:.1f}" rx="{rx * s:.1f}" fill="{fill}"/>'
    hook = f'<path d="M{cx:.1f} {top:.1f} v{28 * s:.1f}" stroke="{CREAM}" stroke-width="{10 * s:.1f}" stroke-linecap="round"/>'
    return hook + r(92, 80, 72, 20, 10, CAP) + r(98, 98, 60, 78, 24, BODY) + r(112, 112, 32, 48, 14, GLOW) + r(100, 176, 56, 16, 8, CAP)


def back(w, h):
    hills = (f'<rect width="{w}" height="{h}" fill="{FIELD}"/>'
             f'<ellipse cx="{w * 0.5:.1f}" cy="{h * 1.18:.1f}" rx="{w * 0.62:.1f}" ry="{h * 0.62:.1f}" fill="{HILL}"/>'
             f'<ellipse cx="{w * 0.08:.1f}" cy="{h * 1.05:.1f}" rx="{w * 0.30:.1f}" ry="{h * 0.33:.1f}" fill="{HILL_DARK}"/>'
             f'<ellipse cx="{w * 0.94:.1f}" cy="{h * 1.08:.1f}" rx="{w * 0.28:.1f}" ry="{h * 0.34:.1f}" fill="{HILL_DARK}"/>')
    return svg(w, h, hills)


def middle(w, h):
    halo = ''.join(f'<circle cx="{w * 0.5:.1f}" cy="{h * 0.52:.1f}" r="{h * k:.1f}" fill="{GLOW}" fill-opacity="{a}"/>'
                   for k, a in ((0.42, 0.10), (0.32, 0.14), (0.23, 0.18)))
    stars = ''.join(f'<circle cx="{w * x:.1f}" cy="{h * y:.1f}" r="{h * 0.012:.1f}" fill="{CREAM}" fill-opacity="0.8"/>'
                    for x, y in ((0.16, 0.22), (0.27, 0.12), (0.74, 0.16), (0.86, 0.28), (0.63, 0.08)))
    return svg(w, h, halo + stars)


def front(w, h):
    s = h * 0.62 / 140.0          # the lantern (hook to base, 140 icon px) fills about 62 % of the height
    return svg(w, h, lantern(w * 0.5, h * 0.16, s))


def shelf(w, h):
    body = (f'<rect width="{w}" height="{h}" fill="{FIELD}"/>'
            f'<rect width="{w}" height="{h * 0.5:.1f}" fill="{FIELD_DARK}" fill-opacity="0.35"/>'
            f'<ellipse cx="{w * 0.25:.1f}" cy="{h * 1.25:.1f}" rx="{w * 0.42:.1f}" ry="{h * 0.62:.1f}" fill="{HILL_DARK}"/>'
            f'<ellipse cx="{w * 0.72:.1f}" cy="{h * 1.30:.1f}" rx="{w * 0.48:.1f}" ry="{h * 0.66:.1f}" fill="{HILL}"/>'
            f'<path d="M{w * 0.44:.1f} {h:.1f} Q{w * 0.52:.1f} {h * 0.78:.1f} {w * 0.62:.1f} {h * 0.70:.1f} '
            f'L{w * 0.66:.1f} {h * 0.72:.1f} Q{w * 0.58:.1f} {h * 0.82:.1f} {w * 0.56:.1f} {h:.1f} Z" fill="{CAP}" fill-opacity="0.75"/>')
    # A string of lanterns across the lane, each with a soft glow.
    line = f'<path d="M0 {h * 0.12:.1f} Q{w * 0.5:.1f} {h * 0.34:.1f} {w:.1f} {h * 0.12:.1f}" stroke="{CREAM}" stroke-width="{h * 0.008:.1f}" fill="none"/>'
    lamps = ''
    for i in range(7):
        x = w * (0.1 + i * 0.133)
        t = x / w
        y = h * (0.12 + 0.44 * t * (1 - t))   # on the string: the quadratic curve above, x linear in t
        s = h * (0.30 if i == 3 else 0.22) / 140.0
        lamps += f'<circle cx="{x:.1f}" cy="{y + 95 * s:.1f}" r="{90 * s:.1f}" fill="{GLOW}" fill-opacity="0.16"/>' + lantern(x, y, s)
    return svg(w, h, body + line + lamps)


# Apple Human Interface Guidelines, tvOS app icons and Top Shelf images (layered app icon, 1x and 2x).
SIZES = {
    'app_icon': {'layers': ['back', 'middle', 'front'], 'sizes': {'1x': [400, 240], '2x': [800, 480]}},
    'app_icon_app_store': {'layers': ['back', 'middle', 'front'], 'sizes': {'1x': [1280, 768]}},
    'top_shelf': {'sizes': {'1x': [1920, 720], '2x': [3840, 1440]}},
    'top_shelf_wide': {'sizes': {'1x': [2320, 720], '2x': [4640, 1440]}},
}


def main():
    src = OUT / 'src'
    src.mkdir(exist_ok=True)
    # Sources at the base size of each aspect; the rasterizer scales them (SVG, so no loss).
    (src / 'app_icon_back.svg').write_text(back(400, 240))
    (src / 'app_icon_middle.svg').write_text(middle(400, 240))
    (src / 'app_icon_front.svg').write_text(front(400, 240))
    (src / 'top_shelf.svg').write_text(shelf(1920, 720))
    (src / 'top_shelf_wide.svg').write_text(shelf(2320, 720))
    (OUT / 'brand.json').write_text(json.dumps(SIZES, indent=2) + '\n')
    print('wrote', sorted(p.name for p in src.iterdir()))


if __name__ == '__main__':
    main()
