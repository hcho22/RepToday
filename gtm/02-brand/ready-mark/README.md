# Ready Mark assets

Original brand assets rendered from the spec in [`../brand-guidelines.md`](../brand-guidelines.md) §3 (Logo) and §4 (Color).
These are derived from the project's own written spec - **not** third-party assets, so no `docs/asset-attribution.md` row is owed (that ledger is for third-party assets only).

## Construction
Two shapes: a rounded-square stroke (the screen) holding one filled circle in its lower third (the Start button).
Relative to the square's side: corner radius 22%, stroke weight 7%, circle diameter 30% centered horizontally with its center at 70% of the square's height.
Colors are exactly Moss `#2E6B4E` and Bone `#F1EEE8`. No gradients, no gloss, no rotation, no added glyphs.

## Files (in `gtm/02-brand/`)
| File | Use |
|------|-----|
| `ready-mark.svg` | The mark itself, Moss on transparent (matches the §3 reference SVG exactly). |
| `ready-mark-app-icon.svg` | App-icon / avatar lockup: Moss background, mark in Bone. |
| `ready-mark-app-icon-1024.png` | 1024×1024 render of the app icon - avatar / App Store master. |
| `ready-mark-app-icon-512.png` | 512×512 render of the app icon - social profile avatar size. |
| `ready-mark-moss-1024.png` | 1024×1024 mark in Moss on transparent, ≥25% clear space on all sides. |

## Regenerating the PNGs
Rendered with `rsvg-convert`:
```sh
cd gtm/02-brand
rsvg-convert -w 1024 -h 1024 ready-mark-app-icon.svg -o ready-mark-app-icon-1024.png
rsvg-convert -w 512  -h 512  ready-mark-app-icon.svg -o ready-mark-app-icon-512.png
```
The transparent Moss PNG uses a clear-space variant of the mark (square side 60% of the canvas, centered - 33% clear space each side).
```sh
rsvg-convert -w 1024 -h 1024 ready-mark/ready-mark-moss-clearspace.svg -o ready-mark-moss-1024.png
```
