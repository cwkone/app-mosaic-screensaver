#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build QA
xcrun swiftc -swift-version 5 -O -whole-module-optimization -module-name AppMosaicDev \
    Sources/Model.swift Sources/Automation.swift Sources/Catalog.swift Sources/Artwork.swift Sources/Renderer.swift \
    Sources/ScheduleOptions.swift Sources/Options.swift Sources/MosaicView.swift Sources/Preview.swift \
    -framework AppKit -framework ScreenSaver -framework QuartzCore -framework CoreLocation -o build/AppMosaicPreview-dev
./build/AppMosaicPreview-dev "$@"
