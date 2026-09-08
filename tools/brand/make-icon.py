#!/usr/bin/env python3
"""Render the Sift logo into the textures the addon ships.

  python3 tools/brand/make-icon.py [preview.png] [--concepts concepts.png]
  python3 tools/brand/make-icon.py --minimap-preview minimap.png

Writes Media/icon.tga (framed) and Media/minimap-icon.tga (frameless),
both 64 x 64, 32-bit uncompressed, and tools/brand/sift-icon-256.png
(framed, for branding). With a path argument it also writes a contact
sheet showing the minimap mark at in-game sizes over game-like grounds.

Needs rsvg-convert on PATH and Pillow.
"""
import argparse
import os
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SVG = os.path.join(HERE, "sift-logo.svg")
MEDIA = os.path.join(ROOT, "Media")


def render(size, source=SVG, minimap=False):
    """Rasterize the SVG at size x size and return an RGBA image."""
    svg_input = None
    if minimap:
        root = ET.parse(source).getroot()
        background = next(child for child in root if child.get("id") == "background")
        root.remove(background)
        # The keeper spans x=44..212, y=43..218. Enlarge it uniformly,
        # leaving >5% on every side for minimap collectors' texture crop.
        root.set("viewBox", "26 28 204 204")
        svg_input = ET.tostring(root, encoding="utf-8")
    png = subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size)] + ([] if minimap else [source]),
        input=svg_input, check=True, capture_output=True).stdout
    from io import BytesIO
    return Image.open(BytesIO(png)).convert("RGBA")


def downsample(big, size):
    return big.resize((size, size), Image.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("preview", nargs="?", help="write the in-game size preview")
    parser.add_argument("--concepts", help="write a comparison of the three new marks")
    parser.add_argument("--minimap-preview", help="compare framed and frameless minimap textures")
    args = parser.parse_args()
    os.makedirs(MEDIA, exist_ok=True)
    big = render(1024)
    minimap = render(1024, minimap=True)

    icon64 = downsample(big, 64)
    icon64.save(os.path.join(MEDIA, "icon.tga"), format="TGA")
    downsample(minimap, 64).save(os.path.join(MEDIA, "minimap-icon.tga"), format="TGA")
    downsample(big, 256).save(os.path.join(HERE, "sift-icon-256.png"), format="PNG")

    if args.preview:
        sheet(minimap, args.preview)
    if args.concepts:
        concepts(args.concepts)
    if args.minimap_preview:
        minimap_comparison(big, minimap, args.minimap_preview)


def minimap_comparison(brand, minimap, path):
    """Rendered comparison; the cropped row models EllesmereUI's 5% inset."""
    out = Image.new("RGBA", (800, 520), "#101820")
    draw = ImageDraw.Draw(out)
    label = ImageFont.load_default(size=20)
    small = ImageFont.load_default(size=14)
    for column, (big, title) in enumerate([(brand, "Before / framed"), (minimap, "After / frameless")]):
        x = column * 400
        draw.text((x + 24, 24), title, font=label, fill="#eee9db")
        out.alpha_composite(downsample(big, 160), (x + 120, 70))
        icon64 = downsample(big, 64)
        for row, (caption, ground, cropped) in enumerate([
            ("Full texture / standard minimap", "#2e3e26", False),
            ("5% crop / EllesmereUI bar", "#080c0e", True),
        ]):
            y = 260 + row * 110
            draw.rectangle((x + 16, y, x + 384, y + 98), fill=ground)
            draw.text((x + 28, y + 10), caption, font=small, fill="#eee9db")
            for size, center in [(18, 65), (20, 155), (24, 245), (32, 335)]:
                # Fractional source bounds match SetTexCoord(0.05, 0.95, ...).
                bounds = (3.2, 3.2, 60.8, 60.8) if cropped else None
                img = icon64.resize((size, size), Image.BILINEAR, box=bounds)
                out.alpha_composite(img, (x + center - size // 2, y + 36 + (32 - size) // 2))
                draw.text((x + center, y + 76), str(size) + " px", font=small,
                          fill="#94a6ad", anchor="mt")
    draw.text((24, 490), "Rendered texture preview; cropped rows simulate the installed EllesmereUI code.",
              font=small, fill="#94a6ad")
    out.save(path, format="PNG")


def concepts(path):
    """Compare new designs, including small sizes scaled from the 64 px texture."""
    options = [
        ("sift-logo.svg", "01 / THE KEEPER", "Find the loot worth keeping.", "SELECTED"),
        ("sift-sigil.svg", "02 / THE SIGIL", "A chiseled S with a jade facet.", "ALTERNATIVE"),
        ("sift-verdict.svg", "03 / THE VERDICT", "A confident cut through the noise.", "ALTERNATIVE"),
    ]
    out = Image.new("RGBA", (1320, 830), "#0c1218")
    draw = ImageDraw.Draw(out)
    ink, muted, jade = "#eee9db", "#94a6ad", "#8de0bd"
    heading = ImageFont.load_default(size=44)
    label = ImageFont.load_default(size=18)
    body = ImageFont.load_default(size=16)
    small = ImageFont.load_default(size=12)
    draw.text((48, 30), "SIFT", font=heading, fill=ink)
    draw.text((50, 92), "Good loot. Clear decisions.", font=label, fill=muted)
    draw.text((1272, 53), "ICON STUDIES / JADE + GOLD", font=small, fill=jade, anchor="ra")
    for i, (filename, title, description, status) in enumerate(options):
        x = 40 + i * 428
        draw.rounded_rectangle((x, 146, x + 404, 786), radius=18, fill="#141e26")
        draw.text((x + 24, 170), title, font=label, fill=ink)
        draw.text((x + 24, 201), status, font=small, fill=jade if i == 0 else muted)
        big = render(1024, os.path.join(HERE, filename))
        out.alpha_composite(downsample(big, 256), (x + 74, 253))
        draw.text((x + 202, 541), description, font=body, fill=muted, anchor="mt")
        draw.line((x + 24, 586, x + 380, 586), fill="#2b3941")
        icon64 = downsample(big, 64)
        for size, center in [(64, 68), (32, 174), (20, 262), (18, 336)]:
            img = icon64 if size == 64 else icon64.resize((size, size), Image.BILINEAR)
            out.alpha_composite(img, (x + center - size // 2, 609 + (64 - size) // 2))
            draw.text((x + center, 690), str(size) + " px", font=small, fill=muted, anchor="mt")
        draw.text((x + 202, 749), "ACTUAL TEXTURE SIZES", font=small, fill=muted, anchor="mt")
    out.save(path, format="PNG")


def sheet(big, path):
    """Contact sheet: the mark at 256, 64, 32, 20 and 18 px on a dark
    green ground (a minimap) and on the addon list's parchment-ish grey."""
    grounds = [(46, 62, 38, 255), (58, 58, 64, 255)]
    sizes = [256, 64, 32, 20, 18]
    pad = 24
    width = pad + sum(s + pad for s in sizes)
    height = pad + (256 + pad) * len(grounds)
    out = Image.new("RGBA", (width, height), (20, 20, 20, 255))
    draw = ImageDraw.Draw(out)
    y = pad
    for g in grounds:
        draw.rectangle([0, y - pad // 2, width, y + 256 + pad // 2], fill=g)
        x = pad
        for s in sizes:
            # Downsample through 64 for the small sizes, the way WoW will
            # scale the shipped texture, so the preview is honest.
            src = downsample(big, 64) if s < 64 else big
            img = src.resize((s, s), Image.BILINEAR if s < 64 else Image.LANCZOS)
            out.alpha_composite(img, (x, y + 256 - s))
            x += s + pad
        y += 256 + pad
    out.save(path, format="PNG")


if __name__ == "__main__":
    main()
