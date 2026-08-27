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


def build_vision_layers(build_dir: Path, out_dir: Path) -> dict:
    """
    The three parallax layers visionOS wants.

    visionOS does not take a flat 1024 PNG. It wants an AppIcon.solidimagestack
    of back, middle and front layers, which it separates in depth and shifts as
    the wearer moves. An .appiconset with a single image builds without
    complaint and produces a bundle with no icon at all, which is what the
    archive verifier caught.

    The split is the obvious one for this app: the ground behind, the Pfam
    point cloud in the middle, the query comet in front. The parallax then
    means something rather than being decoration.
    """
    families = json.loads(
        gzip.open(build_dir / "families.json.gz", "rt", encoding="utf-8").read()
    )
    coords = np.load(build_dir / "umap3d.npy")
    scale = 4
    big = (SIZE * scale, SIZE * scale)

    spread = coords.std(axis=0)
    ax, ay = np.argsort(-spread)[:2]
    xs, ys = coords[:, ax], coords[:, ay]
    span = max(np.percentile(np.abs(xs), 99.5), np.percentile(np.abs(ys), 99.5))
    centre = SIZE * scale / 2
    extent = SIZE * scale * 0.42 / max(span, 1e-6)

    # Back: the ground, opaque, with a faint central glow so the middle layer
    # has something to sit against when the layers separate.
    back = Image.new("RGB", big, BG)
    glow = Image.new("RGB", big, (0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        [centre - SIZE * scale * 0.34, centre - SIZE * scale * 0.34,
         centre + SIZE * scale * 0.34, centre + SIZE * scale * 0.34],
        fill=(14, 24, 46),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(radius=40 * scale))
    back = Image.fromarray(np.clip(
        np.asarray(back, np.int16) + np.asarray(glow, np.int16), 0, 255).astype(np.uint8))

    # Middle: the families, transparent so the ground shows through.
    middle = Image.new("RGBA", big, (0, 0, 0, 0))
    draw = ImageDraw.Draw(middle)
    for family, x, y in zip(families, xs, ys):
        px = centre + float(x) * extent
        py = centre + float(y) * extent
        if not (0 <= px < big[0] and 0 <= py < big[1]):
            continue
        colour = clan_colour(family["clan_hue"])
        radius = 2.4 * scale if family["clan"] else 1.7 * scale
        alpha = 110 if family["is_duf"] else 255
        draw.ellipse([px - radius, py - radius, px + radius, py + radius],
                     fill=colour + (alpha,))

    # Front: the comet alone, so it floats clear of the cloud.
    front = Image.new("RGBA", big, (0, 0, 0, 0))
    cd = ImageDraw.Draw(front)
    cx, cy = centre + SIZE * scale * 0.20, centre - SIZE * scale * 0.18
    r = 13 * scale
    cd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=FLARE + (255,))
    for i in range(1, 26):
        t = i / 26
        tr = r * (1 - t) * 0.85
        tx, ty = cx - i * 5.5 * scale, cy + i * 4.6 * scale
        cd.ellipse([tx - tr, ty - tr, tx + tr, ty + tr],
                   fill=FLARE + (int(255 * (1 - t) * 0.8),))
    front = front.filter(ImageFilter.GaussianBlur(radius=1.4 * scale))

    stack = out_dir / "AppIcon.solidimagestack"

    # Ordered FRONT to BACK, not back to front. Xcode requires that the last
    # layer in the array be fully opaque, and rejects the build with "The last
    # visionOS App Icon Layer with content, 'Front', must be a fully opaque
    # bitmap. The pixel at position (0, 0) has an alpha value of 0." The last
    # entry is the backmost layer, so the opaque ground goes last.
    layers = [("Front", front, "RGBA"), ("Middle", middle, "RGBA"), ("Back", back, "RGB")]
    if stack.exists():
        import shutil
        shutil.rmtree(stack)
    stack.mkdir(parents=True)
    (stack / "Contents.json").write_text(json.dumps({
        "info": {"author": "xcode", "version": 1},
        "layers": [{"filename": f"{name}.solidimagestacklayer"} for name, _, _ in layers],
    }, indent=2))

    for name, image, mode in layers:
        layer = stack / f"{name}.solidimagestacklayer"
        content = layer / "Content.imageset"
        content.mkdir(parents=True)
        (layer / "Contents.json").write_text(json.dumps(
            {"info": {"author": "xcode", "version": 1}}, indent=2))
        (content / "Contents.json").write_text(json.dumps({
            "images": [{"filename": f"{name}.png", "idiom": "vision", "scale": "2x"}],
            "info": {"author": "xcode", "version": 1},
        }, indent=2))
        image.resize((SIZE, SIZE), Image.LANCZOS).convert(mode).save(
            content / f"{name}.png", "PNG")

    return {"stack": str(stack), "layers": [n for n, _, _ in layers]}


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    print(json.dumps(
        build(root / "assets/build", root / "assets/icon/AppIcon-1024.png"), indent=2
    ))
    print(json.dumps(build_vision_layers(
        root / "assets/build",
        root / "Apps/visionOS/Assets.xcassets"), indent=2))
