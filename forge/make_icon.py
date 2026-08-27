"""
The app icon, drawn from the real Pfam map.

Not a placeholder glyph: this renders the actual UMAP projection the Galaxy
shows, so the icon is the thing the app is about. Points are coloured by their
real clan hue over the Deep Field ground.

Two rules the App Store enforces and PIL will happily break for you:
the icon must be RGB with no alpha channel (PIL gives you RGBA by default),
and it must be exactly square at 1024.
"""

from __future__ import annotations

import gzip
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
BG = (7, 11, 20)              # bgDeep
NOVA = (94, 234, 212)         # accentNova
PULSAR = (167, 139, 250)      # accentPulsar
FLARE = (251, 191, 36)        # accentFlare


def clan_colour(hue: float) -> tuple[int, int, int]:
    """The same teal-to-violet arc the app uses, so icon and Galaxy agree."""
    if hue < 0:
        return (138, 150, 173)
    import colorsys
    arc = 0.42 + hue * 0.36
    r, g, b = colorsys.hsv_to_rgb(arc, 0.62, 0.95)
    return (int(r * 255), int(g * 255), int(b * 255))


def build(build_dir: Path, out: Path) -> dict:
    families = json.loads(
        gzip.open(build_dir / "families.json.gz", "rt", encoding="utf-8").read()
    )
    coords = np.load(build_dir / "umap3d.npy")

    # Render at 4x and downsample: point clouds alias badly at icon size, and
    # supersampling is cheaper to reason about than per-point antialiasing.
    scale = 4
    canvas = Image.new("RGB", (SIZE * scale, SIZE * scale), BG)
    glow = Image.new("RGB", (SIZE * scale, SIZE * scale), (0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    glow_draw = ImageDraw.Draw(glow)

    # Look down the two most spread axes, and fill the frame.
    spread = coords.std(axis=0)
    ax, ay = np.argsort(-spread)[:2]
    xs, ys = coords[:, ax], coords[:, ay]
    span = max(np.percentile(np.abs(xs), 99.5), np.percentile(np.abs(ys), 99.5))
    centre = SIZE * scale / 2
    extent = SIZE * scale * 0.46 / max(span, 1e-6)

    drawn = 0
    for family, x, y in zip(families, xs, ys):
        px = centre + float(x) * extent
        py = centre + float(y) * extent
        if not (0 <= px < SIZE * scale and 0 <= py < SIZE * scale):
            continue
        colour = clan_colour(family["clan_hue"])
        radius = 2.2 * scale if family["clan"] else 1.6 * scale
        if family["is_duf"]:
            colour = tuple(int(c * 0.45) for c in colour)
        draw.ellipse([px - radius, py - radius, px + radius, py + radius], fill=colour)
        if family["clan"]:
            glow_draw.ellipse(
                [px - radius * 2, py - radius * 2, px + radius * 2, py + radius * 2],
                fill=tuple(int(c * 0.35) for c in colour),
            )
        drawn += 1

    glow = glow.filter(ImageFilter.GaussianBlur(radius=9 * scale))
    canvas = Image.blend(canvas, Image.blend(canvas, glow, 0.0), 0.0)
    canvas = Image.fromarray(
        np.clip(
            np.asarray(canvas, dtype=np.int16) + np.asarray(glow, dtype=np.int16),
            0, 255,
        ).astype(np.uint8)
    )

    # One amber comet: the app's own mark for a query dropped into the map.
    comet = Image.new("RGB", canvas.size, (0, 0, 0))
    cd = ImageDraw.Draw(comet)
    cx, cy = centre + SIZE * scale * 0.22, centre - SIZE * scale * 0.20
    r = 11 * scale
    cd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=FLARE)
    for i in range(1, 26):
        t = i / 26
        tr = r * (1 - t) * 0.85
        tx = cx - i * 5.5 * scale
        ty = cy + i * 4.6 * scale
        cd.ellipse(
            [tx - tr, ty - tr, tx + tr, ty + tr],
            fill=tuple(int(c * (1 - t) * 0.75) for c in FLARE),
        )
    comet = comet.filter(ImageFilter.GaussianBlur(radius=1.6 * scale))
    canvas = Image.fromarray(
        np.clip(
            np.asarray(canvas, dtype=np.int16) + np.asarray(comet, dtype=np.int16),
            0, 255,
        ).astype(np.uint8)
    )

    canvas = canvas.resize((SIZE, SIZE), Image.LANCZOS)

    # The App Store rejects an icon with an alpha channel, and every PIL path
    # above can quietly hand back RGBA. Assert rather than hope.
    if canvas.mode != "RGB":
        canvas = canvas.convert("RGB")
    assert canvas.mode == "RGB", canvas.mode
    assert canvas.size == (SIZE, SIZE), canvas.size

    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, "PNG")

    check = Image.open(out)
    return {
        "path": str(out),
        "size": check.size,
        "mode": check.mode,
        "has_alpha": check.mode in ("RGBA", "LA") or "transparency" in check.info,
        "families_drawn": drawn,
        "kb": round(out.stat().st_size / 1024, 1),
    }


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    print(json.dumps(
        build(root / "assets/build", root / "assets/icon/AppIcon-1024.png"), indent=2
    ))
