<img width="231" height="150" alt="kuller" src="docs/logo.svg" />

# kuller

Cull images from the command line. Point it at files or folders, flick through
them with two keys, and get your picks and rejects side by side at the end.

The image window *is* the image: it takes the picture's aspect ratio, floats
over your desktop, drags by grabbing it and resizes by pinching. Thumbnails
live in a panel docked to the left edge of the screen.

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

## Keys

While culling:

| | |
| --- | --- |
| `p` / `x` | Pick / reject, then advance |
| `j` / `k`, `←` / `→` | Next / previous, without deciding |
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
