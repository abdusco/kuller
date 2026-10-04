<img width="231" height="150" alt="kuller" src="docs/logo.svg" />

# kuller

Cull images from the command line. Point it at files or folders, flick through
them with two keys, and get your picks and rejects side by side at the end.

The image window *is* the image: it takes the picture's aspect ratio, floats
over your desktop, drags by grabbing it and resizes by pinching. Thumbnails
live in a panel docked to the left edge of the screen.

Pinching grows the window up to the display edges, then keeps zooming the
image inside it. Drag or scroll with two fingers to pan when zoomed beyond
the window; double-click to reset the image and window to their fitted size.

## Build

```sh
./build.sh          # -> build/kuller
```

A single `swiftc` invocation, no Xcode project and no package manifest.
Requires macOS 14+.

## Usage

```sh
kuller <path> [path ...]
kuller --copy-picks-to ~/Desktop/selects ~/Pictures/shoot
```

Folders are scanned recursively for `jpg`, `jpeg`, `png`, `tiff`, `tif`,
`gif`, `bmp` and `webp` files.

| Option | |
| --- | --- |
| `-h`, `--help` | Show help and exit |
| `--version` | Show version and exit |
| `--copy-picks-to <dir>` | On finishing, copy picks to `<dir>` (created if needed) and quit, skipping the review screen |

## Cropping

Press `c` while culling to crop the current image. The screen dims to a
full-screen overlay with the image centered and padded on all sides; drag any
corner or edge handle to resize, or drag inside the image to start a fresh
selection. Pick an aspect ratio from the dropdown, or cycle through the 13
built-in ratios (original, free, 9:16, 10:16, 2:3, 3:4, 4:5, 1:1, 5:4, 4:3,
3:2, 16:10, 16:9) with `⌥+`/`⌥-`; `⌥1`-`⌥9` jump straight to one, `⌥0` to Free.
The last ratio used carries over to the next image you crop.

Confirming a crop (`↩`) doesn't touch the original file — it inserts a new,
independent "virtual copy" right below it (named `photo_crop1.jpg`,
`photo_crop2.jpg`, ...) that can be picked, rejected, Quick Looked, copied, or
deleted on its own. The crop is applied lazily wherever the copy's bytes
actually leave the app — thumbnails, Quick Look, `⌘C`, drag-to-Finder, and
`--copy-picks-to` export all hand out the cropped image, at full resolution.

| | |
| --- | --- |
| `c` | Enter crop mode on the current image |
| drag corner / edge | Resize the crop area |
| drag inside image | Start a new crop area |
| `⌥+` / `⌥-` | Cycle aspect ratio |
| `⌥1`-`⌥9`, `⌥0` | Jump to a specific ratio, or Free |
| `↩` | Confirm — creates or updates the cropped copy |
| `esc` | Cancel, discarding changes to this crop |

## Keys

While culling:

| | |
| --- | --- |
| `p` / `x` | Pick / reject, then advance |
| `j` / `k`, `←` / `→` | Next / previous, without deciding |
| `c` | Crop the current image (see [Cropping](#cropping)) |
| `i` | Flash name, pixel dimensions, and file creation/modification dates for three seconds |
| `⌘↩` | Finish now — undecided images become rejects |
| `esc`, `⌘W` | Exit (confirms if anything is still undecided) |
| `⌘Q` | Quit |

In the review screen, both columns support rubber-band selection and dragging
files out to Finder or across to the other column:

| | |
| --- | --- |
| `p` / `x` | Move the selection to Picks / Rejects |
| `space` | Quick Look the selection |
| `⌘A` | Select all in the focused column |
| `⌘C` | Copy the selection as files |

Selecting cropped copies starts preparing their full-resolution files in the
background, so previewing, copying, and dragging can reuse them.
