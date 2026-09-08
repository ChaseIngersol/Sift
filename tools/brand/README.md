# Sift icon

The keeper (`sift-logo.svg`) is the selected master: a jade loot gem above
a gold sieve, with three grains falling through. It expresses Sift's job
of finding what is worth keeping, including value a player might miss.
The jade and gold echo the addon's equip and hold colors. Branding uses the
dark medallion. Everything in game (the 32 px header mark on every Sift
window, the minimap, the addon compartment, the addon list, and the toast's
Edit Mode preview) uses the larger, frameless version of the mark.

Two independent alternatives are included:

- `sift-sigil.svg`: a chiseled gold S with a jade facet; strongest as a monogram.
- `sift-verdict.svg`: a gold gem with a check cut through it; emphasizes advice.

All three are self-contained vectors with no fonts, embedded bitmaps,
external resources, or blur filters. The `background` and `mark` groups
can be edited separately.

## Build

Requires `rsvg-convert` and Python with Pillow 10.1 or later. From the repository root:

```sh
python3 tools/brand/make-icon.py /tmp/sift-size-preview.png --concepts tools/brand/sift-concepts.png
python3 tools/brand/make-icon.py --minimap-preview tools/brand/sift-minimap-preview.png
```

This rebuilds `Media/icon.tga` and `Media/minimap-icon.tga` (both 64 x 64,
uncompressed RGBA), plus `sift-icon-256.png`, and produces the requested
preview sheets. The minimap sheet shows dark green and gray backgrounds. Small
previews are scaled from the shipped 64 px texture, including the 18 px
size used by `UI/Minimap.lua`. The concepts sheet shows the framed designs.

The minimap texture is derived from the master SVG by removing the
`background` group and tightening the viewBox to `26 28 204 204`. The mark
is about 25% larger than in the branding texture, with transparent margins
that survive EllesmereUI's 5% texture crop. That crop cuts the circular rim
of the framed texture into flat edges. The [minimap comparison](sift-minimap-preview.png)
shows both versions at actual sizes, with and without the crop; it is a
rendered preview, not an in-game screenshot. Despite its filename,
`minimap-icon.tga` is shared by all small in-game Sift icons. The TOC's
`IconTexture` selects it for both the addon list and addon compartment.
The framed `icon.tga` is kept for branding only; actual loot toasts
continue to show the item's own icon.

To adopt an alternative, replace the contents of `sift-logo.svg` with that
SVG and run the script. Adjust the minimap viewBox in the renderer if the
new mark has different bounds. No Lua or TOC changes are needed. Reload
the game to see the new texture.
