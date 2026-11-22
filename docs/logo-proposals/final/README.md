# Alt Right — final

Your composition, kept exactly. The flat blue became a gradient, in eight flavours.

- [`sheet.png`](sheet.png) — app icon at every size, tile-free mark, menu-bar options
- [`variants-sheet.png`](variants-sheet.png) — the eight gradients side by side

```
final/
├── icon.svg                      current pick (= variants/01-azure.svg)
├── icon-{1024,512,256,128,64,32,16}.png
├── AppIcon.icns                  built from 01-azure, ready to drop in AltRight/
├── variants/                     8 gradients × {svg, 1024, 256, 128, 64, 32}
├── variants-sheet.png            the 8 of them on one page
├── glyph-mono.svg / glyph-white.svg   tile-free mark, one ink colour, eyes knocked out
├── menubar/                      ar-pair · ar-eyes · r-face  (svg + 18 & 36 px PNG)
└── make_variants.py              regenerates variants/ from the constants below
```

## Geometry (unchanged from `icon-1024.png`)

Measured off the PNG pixel by pixel, not eyeballed:

| element | coordinates |
| --- | --- |
| tile | rounded rect 100,100 → 924,924, r 186 (macOS icon grid) |
| A | apex (403,304), base (243,726)–(563,726) |
| A eyes | (365,591) r 20 · (445,591) r 20 |
| R | (599,303) – (803,514) – (599,726) |
| R leg | (599,640) – (685,726) – (599,726) |
| R eyes | (659,451) r 17.5 · (701,491) r 17.5 |
| eye ink | `#0A0E22` (dark ink on the white shapes, so the faces survive any background) |

`make_variants.py` holds these once; every SVG is generated from them, so the marks cannot
drift between variants.

## Gradient variants

| # | Name | Stops | Notes |
| --- | --- | --- | --- |
| 01 | **Azure** | `#8FB6FF → #3E78FA → #1838B4` | current pick: light top-left, deep bottom-right, soft top glow |
| 02 | **Cobalt** | `#3A6AFF → #2246D6 → #0D2172` | straighter, deeper, no glow — the sober one |
| 03 | **Glacier** | `#A9C7FF → #6D97FF → #3A63E8` | pale and airy, strongest highlight |
| 04 | **Indigo** | `#8A96FF → #4C57EC → #1F199B` | blue leaning violet |
| 05 | **Midnight** | `#3364E8 → #132569 → #04071C` | near-black bottom, most contrast |
| 06 | **Teal** | `#5AE6CD → #17B0A6 → #056B6D` | alternate |
| 07 | **Ember** | `#FFC57E → #FF8A47 → #D53E1C` | alternate |
| 08 | **Night** | `#1B2456 → #0C1130 → #06081B` | the earlier dark version, same geometry, with five stars |

All of them share the same white marks and dark eyes, so switching variants is literally
swapping the background gradient.

## Menu bar

18×18 template images (black + alpha), same geometry as the icon, fitted and centred:

- `ar-pair` — A + R, no faces; cleanest at 18 pt. **Recommended.**
- `ar-eyes` — same with the eyes knocked out (dots bumped to 1.6 / 1.4 px so they survive).
- `r-face` — the R alone, scaled on its own; boldest, but loses the "AR".

## Rebuilding

```bash
python3 make_variants.py     # rewrite variants/*.svg from the constants
cd .. && ./render.sh         # renders every PNG, refreshes final/icon.* from 01-azure
```

To change which variant is "the icon", point `cp final/variants/<name>.svg final/icon.svg` (the
render script currently copies `01-azure`), then rebuild `AppIcon.icns` from its 1024 PNG.

## Wiring it into the app

```bash
cp docs/logo-proposals/final/AppIcon.icns AltRight/AppIcon.icns
```

The menu bar still needs the small Swift change (`MenuBarExtra(…, systemImage:)` →
template `Image("MenuBarAR")`) plus an asset catalog, which the project does not have yet.
Say the word and I will add it.
