#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SAVER="$HOME/Library/Application Support/App Mosaic/Builds/App Mosaic.saver"
DEST="$HOME/Library/Screen Savers/App Mosaic.saver"
if [ ! -d "$SAVER" ]; then
    printf 'Build first with ./Scripts/build.sh\n' >&2
    exit 1
fi
# The native custom Finder icon intentionally contains Finder metadata.
codesign --verify --strict=symlinks "$SAVER"
mkdir -p "$HOME/Library/Screen Savers"
if [ -e "$DEST" ]; then
    BACKUP="build/backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    ditto "$DEST" "$BACKUP/App Mosaic.saver"
fi
ditto --rsrc --extattr "$SAVER" "$DEST"
# Reapply through AppKit so Finder also refreshes its cached icon on upgrades.
if [ ! -x build/SetFinderIcon ]; then
    mkdir -p build
    xcrun swiftc Scripts/SetFinderIcon.swift -framework AppKit -o build/SetFinderIcon
fi
./build/SetFinderIcon "$DEST" "$SAVER/Contents/Resources/AppMosaic.icns"
codesign --verify --strict=symlinks "$DEST"
printf 'Installed %s\nSelect App Mosaic in System Settings → Screen Saver.\n' "$DEST"
