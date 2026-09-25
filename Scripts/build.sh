#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --show-sdk-path)"
XCODE_DIR="${APP_MOSAIC_XCODE_DIR:-/Applications/Xcode.app/Contents/Developer}"
XCODE_TOOLCHAIN="$XCODE_DIR/Toolchains/XcodeDefault.xctoolchain"
XCODE_SDK="$XCODE_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
XCODE_SWIFTC="$XCODE_TOOLCHAIN/usr/bin/swiftc"
INTENTS_PROCESSOR="$XCODE_TOOLCHAIN/usr/bin/appintentsmetadataprocessor"
if [[ ! -x "$XCODE_SWIFTC" || ! -x "$INTENTS_PROCESSOR" || ! -d "$XCODE_SDK" ]]; then
    printf 'App Mosaic Focus filters require a complete Xcode installation. Set APP_MOSAIC_XCODE_DIR if Xcode is installed elsewhere.\n' >&2
    exit 1
fi
mkdir -p build dist
COMMON=(Sources/Model.swift Sources/Automation.swift Sources/Catalog.swift Sources/Artwork.swift Sources/Renderer.swift Sources/ScheduleOptions.swift Sources/Options.swift Sources/MosaicView.swift)
MOSAIC_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/app-mosaic.XXXXXX")"
SAVER="$MOSAIC_STAGE/saver-package/App Mosaic.saver"
PREVIEW="$MOSAIC_STAGE/App Mosaic Preview.app"
FOCUS_EXTENSION="$PREVIEW/Contents/Extensions/App Mosaic Focus Intents.appex"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources" "$PREVIEW/Contents/MacOS" "$PREVIEW/Contents/Resources" \
    "$FOCUS_EXTENSION/Contents/MacOS" "$FOCUS_EXTENSION/Contents/Resources"
cp Resources/AppMosaic.icns "$SAVER/Contents/Resources/"
cp Resources/AppMosaic.icns "$PREVIEW/Contents/Resources/"
cp Resources/thumbnail.png Resources/thumbnail@2x.png Resources/thumbnail@4x.png Resources/thumbnail.tiff "$SAVER/Contents/Resources/"
for ARCH in arm64 x86_64; do
    xcrun swiftc -swift-version 5 -O -whole-module-optimization -sdk "$SDK" -target "$ARCH-apple-macosx14.6" \
        -module-name AppMosaic -emit-library "${COMMON[@]}" \
        -framework AppKit -framework ScreenSaver -framework QuartzCore -framework CoreLocation -o "build/AppMosaic-$ARCH"
    xcrun swiftc -swift-version 5 -O -whole-module-optimization -sdk "$SDK" -target "$ARCH-apple-macosx14.6" \
        -module-name AppMosaicPreview "${COMMON[@]}" Sources/Preview.swift \
        -framework AppKit -framework ScreenSaver -framework QuartzCore -framework CoreLocation -o "build/AppMosaicPreview-$ARCH"
done
xcrun lipo -create build/AppMosaic-arm64 build/AppMosaic-x86_64 -output "$SAVER/Contents/MacOS/AppMosaic"
xcrun lipo -create build/AppMosaicPreview-arm64 build/AppMosaicPreview-x86_64 -output "$PREVIEW/Contents/MacOS/AppMosaicPreview"
cat > "$MOSAIC_STAGE/app-intents-protocols.json" <<'JSON'
["AnyResolverProviding","AppEntity","AppEnum","AppExtension","AppIntent","AppIntentsPackage","AppShortcutProviding","AppShortcutsProvider","AppUnionValue","AppUnionValueCasesProviding","DynamicOptionsProvider","EntityQuery","ExtensionPointDefining","IntentValueQuery","Resolver","TransientEntity","_AssistantIntentsProvider","_GenerativeFunctionExtractable","_IntentValueRepresentable"]
JSON
FOCUS_SOURCES=(Sources/Model.swift Sources/Automation.swift Sources/FocusIntents.swift Sources/FocusIntentsExtension.swift)
CONST_VALUES="$MOSAIC_STAGE/AppMosaicFocusIntents.swiftconstvalues"
for ARCH in arm64 x86_64; do
    if [[ "$ARCH" == "x86_64" ]]; then
        "$XCODE_SWIFTC" -swift-version 5 -O -whole-module-optimization -parse-as-library -sdk "$XCODE_SDK" \
            -target "$ARCH-apple-macosx14.6" -module-name AppMosaicFocusIntents "${FOCUS_SOURCES[@]}" \
            -framework AppIntents -framework ExtensionFoundation -framework ScreenSaver \
            -emit-const-values-path "$CONST_VALUES" -Xfrontend -const-gather-protocols-file \
            -Xfrontend "$MOSAIC_STAGE/app-intents-protocols.json" -o "build/AppMosaicFocusIntents-$ARCH"
    else
        "$XCODE_SWIFTC" -swift-version 5 -O -whole-module-optimization -parse-as-library -sdk "$XCODE_SDK" \
            -target "$ARCH-apple-macosx14.6" -module-name AppMosaicFocusIntents "${FOCUS_SOURCES[@]}" \
            -framework AppIntents -framework ExtensionFoundation -framework ScreenSaver \
            -o "build/AppMosaicFocusIntents-$ARCH"
    fi
done
xcrun lipo -create build/AppMosaicFocusIntents-arm64 build/AppMosaicFocusIntents-x86_64 \
    -output "$FOCUS_EXTENSION/Contents/MacOS/AppMosaicFocusIntents"
printf '%s\n' "${FOCUS_SOURCES[@]/#/$PWD/}" > "$MOSAIC_STAGE/focus-sources.list"
printf '%s\n' "$CONST_VALUES" > "$MOSAIC_STAGE/focus-const-values.list"
XCODE_BUILD="$(plutil -extract DTXcodeBuild raw -o - "$XCODE_DIR/../Info.plist")"
"$INTENTS_PROCESSOR" --output "$FOCUS_EXTENSION/Contents/Resources" --toolchain-dir "$XCODE_TOOLCHAIN" \
    --module-name AppMosaicFocusIntents --sdk-root "$XCODE_SDK" --xcode-version "$XCODE_BUILD" \
    --platform-family macOS --deployment-target 14.6 --target-triple x86_64-apple-macosx14.6 \
    --source-file-list "$MOSAIC_STAGE/focus-sources.list" --swift-const-vals-list "$MOSAIC_STAGE/focus-const-values.list" --force
cat > "$SAVER/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>one.cwk.AppMosaic</string>
<key>CFBundleName</key><string>App Mosaic</string>
<key>CFBundleExecutable</key><string>AppMosaic</string>
<key>CFBundleIconFile</key><string>AppMosaic.icns</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>NSPrincipalClass</key><string>AppMosaicView</string>
<key>LSMinimumSystemVersion</key><string>14.6</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocationWhenInUseUsageDescription</key><string>App Mosaic uses an approximate location to calculate local sunrise and sunset for tint schedules.</string>
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
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.6</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocationWhenInUseUsageDescription</key><string>App Mosaic uses an approximate location to calculate local sunrise and sunset for tint schedules.</string>
</dict></plist>
PLIST
cat > "$FOCUS_EXTENSION/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>one.cwk.AppMosaic.Preview.FocusIntents</string>
<key>CFBundleName</key><string>App Mosaic Focus Intents</string>
<key>CFBundleDisplayName</key><string>App Mosaic</string>
<key>CFBundleExecutable</key><string>AppMosaicFocusIntents</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.6</string>
<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
<key>EXAppExtensionAttributes</key><dict><key>EXExtensionPointIdentifier</key><string>com.apple.appintents-extension</string></dict>
<key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.appintents-extension</string></dict>
</dict></plist>
PLIST
cat > "$MOSAIC_STAGE/focus-entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.temporary-exception.shared-preference.read-write</key>
<array><string>one.cwk.AppMosaic</string></array>
</dict></plist>
PLIST
xattr -cr "$SAVER" "$PREVIEW"
codesign --force --sign - "$SAVER"
codesign --force --sign - --entitlements "$MOSAIC_STAGE/focus-entitlements.plist" "$FOCUS_EXTENSION"
codesign --force --sign - "$PREVIEW"
plutil -lint "$SAVER/Contents/Info.plist" "$PREVIEW/Contents/Info.plist" "$FOCUS_EXTENSION/Contents/Info.plist"
codesign --verify --strict "$SAVER"
codesign --verify --deep --strict "$PREVIEW"
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
codesign --verify --deep --strict "$ARTIFACT_DIR/App Mosaic Preview.app"
# Archive the containing directory so the .saver's own Finder flags survive.
ditto -c -k --rsrc --extattr --sequesterRsrc "$MOSAIC_STAGE/saver-package" "dist/App Mosaic.saver.zip"
ditto -c -k --keepParent "$PREVIEW" "dist/App Mosaic Preview.zip"
printf 'Built universal screensaver and preview in %s; ZIP packages are in dist/.\n' "$ARTIFACT_DIR"
