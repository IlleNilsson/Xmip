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
| `xmip-x.ico` | The Windows icon: the PNGs at 16 to 256 packed as they are, nothing redrawn. Made by `Sync-XmipEstate -Brand`. |
| `xmip-x.res` | That icon as a Windows resource, linked into each Rust executable by its `build.rs`. Made by `Sync-XmipEstate -Brand`. |
| `brand.toml` | Every surface that shows the mark or the logo, the copy it keeps and the file that names it. |

**Where it is used.** [`brand.toml`](brand.toml) lists every surface: this
README's repository, `xmip-service`, `xmip-lsp`, the `xmip` command line,
the VS Code extension, the PowerShell module, the desktop and phone app, and
the web GUI. A repository of its own cannot reach this directory, so it keeps
a copy; `Sync-XmipEstate -Brand` writes each copy and the icon and resource
from what is here, and `test/Brand.Test.ps1` fails where a surface does not
name its mark or a copy differs. Change the mark here, run the command, and
every surface follows.

The [project presentation](presentation/README.md) also uses this logo.
Its shared editorial source names the logo for both formats in the same manifest.

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
