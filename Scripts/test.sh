#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build QA
xcrun swiftc -swift-version 5 -O Sources/Model.swift Tests/ModelTests.swift -o build/ModelTests
./build/ModelTests
xcrun swiftc -swift-version 5 -O Sources/Model.swift Sources/Catalog.swift Sources/Artwork.swift Tests/ArtworkTests.swift -framework AppKit -o build/ArtworkTests
./build/ArtworkTests
xcrun swiftc -swift-version 5 -O Sources/Catalog.swift Tests/CatalogTests.swift -framework AppKit -o build/CatalogTests
./build/CatalogTests
xcrun swiftc -swift-version 5 -parse-as-library Tests/BundleSmoke.swift -framework AppKit -framework ScreenSaver -o build/BundleSmoke
./build/BundleSmoke "$HOME/Library/Application Support/App Mosaic/Builds/App Mosaic.saver"
"$HOME/Library/Application Support/App Mosaic/Builds/App Mosaic Preview.app/Contents/MacOS/AppMosaicPreview" --verify
