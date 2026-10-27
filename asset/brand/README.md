# Brand

What the Xmip mark and logo are made of, so the next change starts from the
same values.

## Files

| file | what it is |
|---|---|
| `xmip-x.svg` | The X mark as vectors: the master every PNG of the mark is rendered from. |
| `xmip-x.png` | The X mark, 1024 × 1024, transparent background. |
| `icon/xmip-x-<size>.png` | The X mark at 16, 32, 48, 64, 128, 256 and 512, each downscaled from the 1024 PNG with high-quality bicubic smoothing. |
| `xmip-logo.png` | The logo: the X mark followed by "mip", 888 × 403, transparent background. |

Copies in use: the web GUI's `wwwroot/xmip-x.png` and `wwwroot/xmip-logo.png`,
and the phone and desktop app's `Resources/AppIcon/appicon.png` (the 1024
mark).

## Colors

| name | value | where |
|---|---|---|
| Brand lime | `#75c93b` | The mark and the "mip" letters. The accent color, `--brand` in the web GUI's `xmip.css`. Never a mood color. |
| Fold green | `#2a9e46` | The folded corner inside the mark's lower right arm in `xmip-x.svg` and its PNGs. |
| Logo greens | `#1e963c`, `#27ac3a` | In `xmip-logo.png`, sampled from the original drawing: the mark's fold, and the dot of the "i". |

## Shapes and type

- **The mark** is three shapes in brand lime: an upper V and two lower arms,
  with a gap between them. Its corners are rounded by a 8-unit stroke with
  round joins, on a 456 × 456 view box.
- **The logo** uses the mark as its X. "mip" follows with a 25 px gap, and the
  bottoms of the m, i and p stems sit on the mark's bottom edge; the p's
  descender drops below it.
- **The "mip" letters** are taken from the original logo drawing, not set from
  a font file. They are a thin geometric sans serif. The font they were drawn
  with is not recorded; Century Gothic is the closest installed match.

## How each was made

- The mark was redrawn as vectors from the original 456 × 456 PNG on
  2026-10-27, and rendered to 1024 × 1024 with Microsoft Edge in headless
  mode.
- The logo is the original 2026-09-28 drawing, edited on 2026-10-27: the
  letter X after the mark removed, "mip" moved down onto the mark's baseline
  and in to the 25 px gap.
