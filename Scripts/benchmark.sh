#!/bin/bash
# Repeatable offscreen process benchmark. Optional Git revision, then modes.
set -euo pipefail
cd "$(dirname "$0")/.."
revision="${1:-working}"
if [ "$#" -gt 0 ]; then shift; fi
probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/mosaic-probe.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
for file in Model Catalog Artwork Renderer; do
    if [ "$revision" = working ]; then
        cp "Sources/$file.swift" "$probe_dir/$file.swift"
    else
        git show "$revision:Sources/$file.swift" > "$probe_dir/$file.swift"
    fi
done
xcrun swiftc -swift-version 5 -O "$probe_dir"/*.swift Tests/PerformanceProbe.swift \
    -framework AppKit -framework QuartzCore -o "$probe_dir/probe"
if [ "$#" -eq 0 ]; then set -- dense still tiny large default vertical zero tint mono single double; fi
for mode in "$@"; do "$probe_dir/probe" "$mode"; done
