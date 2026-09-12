#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --show-sdk-path)"
mkdir -p build dist
COMMON=(Sources/Model.swift Sources/Catalog.swift Sources/Artwork.swift Sources/Renderer.swift Sources/Options.swift Sources/MosaicView.swift)
MOSAIC_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/app-mosaic.XXXXXX")"
SAVER="$MOSAIC_STAGE/saver-package/App Mosaic.saver"
PREVIEW="$MOSAIC_STAGE/App Mosaic Preview.app"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources" "$PREVIEW/Contents/MacOS" "$PREVIEW/Contents/Resources"
cp Resources/AppMosaic.icns "$SAVER/Contents/Resources/"
cp Resources/AppMosaic.icns "$PREVIEW/Contents/Resources/"
cp Resources/thumbnail.png Resources/thumbnail@2x.png Resources/thumbnail@4x.png Resources/thumbnail.tiff "$SAVER/Contents/Resources/"
for ARCH in arm64 x86_64; do
    xcrun swiftc -swift-version 5 -O -whole-module-optimization -sdk "$SDK" -target "$ARCH-apple-macosx14.6" \
        -module-name AppMosaic -emit-library "${COMMON[@]}" \
        -framework AppKit -framework ScreenSaver -framework QuartzCore -o "build/AppMosaic-$ARCH"
    xcrun swiftc -swift-version 5 -O -whole-module-optimization -sdk "$SDK" -target "$ARCH-apple-macosx14.6" \
        -module-name AppMosaicPreview "${COMMON[@]}" Sources/Preview.swift \
        -framework AppKit -framework ScreenSaver -framework QuartzCore -o "build/AppMosaicPreview-$ARCH"
done
xcrun lipo -create build/AppMosaic-arm64 build/AppMosaic-x86_64 -output "$SAVER/Contents/MacOS/AppMosaic"
xcrun lipo -create build/AppMosaicPreview-arm64 build/AppMosaicPreview-x86_64 -output "$PREVIEW/Contents/MacOS/AppMosaicPreview"
cat > "$SAVER/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>one.cwk.AppMosaic</string>
<key>CFBundleName</key><string>App Mosaic</string>
<key>CFBundleExecutable</key><string>AppMosaic</string>
<key>CFBundleIconFile</key><string>AppMosaic.icns</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>NSPrincipalClass</key><string>AppMosaicView</string>
<key>LSMinimumSystemVersion</key><string>14.6</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cat > "$PREVIEW/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>one.cwk.AppMosaic.Preview</string>
<key>CFBundleName</key><string>App Mosaic Preview</string>
<key>CFBundleExecutable</key><string>AppMosaicPreview</string>
<key>CFBundleIconFile</key><string>AppMosaic.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.6</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$SAVER" "$PREVIEW"
codesign --force --sign - "$SAVER"
codesign --force --sign - "$PREVIEW"
plutil -lint "$SAVER/Contents/Info.plist" "$PREVIEW/Contents/Info.plist"
codesign --verify --strict "$SAVER"
codesign --verify --strict "$PREVIEW"
# Native Finder icons add metadata outside the signed Contents directory.
# Verify the strict clean bundle first, then retain the requested icon metadata.
xcrun swiftc Scripts/SetFinderIcon.swift -framework AppKit -o build/SetFinderIcon
./build/SetFinderIcon "$SAVER" Resources/AppMosaic.icns
codesign --verify --strict=symlinks "$SAVER"
ARTIFACT_DIR="$HOME/Library/Application Support/App Mosaic/Builds"
mkdir -p "$ARTIFACT_DIR"
ditto --rsrc --extattr "$SAVER" "$ARTIFACT_DIR/App Mosaic.saver"
./build/SetFinderIcon "$ARTIFACT_DIR/App Mosaic.saver" Resources/AppMosaic.icns
ditto --norsrc --noextattr "$PREVIEW" "$ARTIFACT_DIR/App Mosaic Preview.app"
codesign --verify --strict=symlinks "$ARTIFACT_DIR/App Mosaic.saver"
codesign --verify --strict "$ARTIFACT_DIR/App Mosaic Preview.app"
# Archive the containing directory so the .saver's own Finder flags survive.
ditto -c -k --rsrc --extattr --sequesterRsrc "$MOSAIC_STAGE/saver-package" "dist/App Mosaic.saver.zip"
ditto -c -k --keepParent "$PREVIEW" "dist/App Mosaic Preview.zip"
printf 'Built universal screensaver and preview in %s; ZIP packages are in dist/.\n' "$ARTIFACT_DIR"
