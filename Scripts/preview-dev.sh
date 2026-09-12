#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build QA
xcrun swiftc -swift-version 5 -O -whole-module-optimization -module-name AppMosaicDev \
    Sources/Model.swift Sources/Catalog.swift Sources/Artwork.swift Sources/Renderer.swift \
    Sources/Options.swift Sources/MosaicView.swift Sources/Preview.swift \
    -framework AppKit -framework ScreenSaver -framework QuartzCore -o build/AppMosaicPreview-dev
./build/AppMosaicPreview-dev "$@"
