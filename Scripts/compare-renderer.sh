#!/bin/bash
# Compare deterministic model-layer snapshots with the published renderer.
# This does not capture display pixels or validate live animation smoothness.
set -euo pipefail
cd "$(dirname "$0")/.."
revision="${1:-da62bb6}"
comparison_dir="$(mktemp -d "${TMPDIR:-/tmp}/mosaic-comparison.XXXXXX")"
trap 'rm -rf "$comparison_dir"' EXIT
mkdir -p QA/performance
git show "$revision:Sources/Renderer.swift" | sed -e 's/MosaicRenderer/ReferenceRenderer/g' -e 's/MosaicCell/ReferenceCell/g' > "$comparison_dir/ReferenceRenderer.swift"
xcrun swiftc -swift-version 5 -O Sources/Model.swift Sources/Catalog.swift Sources/Artwork.swift Sources/Renderer.swift \
    "$comparison_dir/ReferenceRenderer.swift" Tests/VisualComparison.swift \
    -framework AppKit -framework QuartzCore -o "$comparison_dir/compare"
"$comparison_dir/compare"
