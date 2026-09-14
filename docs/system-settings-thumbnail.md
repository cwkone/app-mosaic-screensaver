# System Settings thumbnail investigation

Last checked September 14, 2026 on macOS 15.7.2 (Intel). This is a diagnostic record, not a claim that the System Settings tile is fixed.

## Observed problem

The installed saver runs and its options load, but the latest visible check of the Screen Saver library showed the generic galaxy image instead of App Mosaic's bundled grid thumbnail. Other third-party savers on the same Mac displayed their own artwork.

## What is now verified

The distribution bundle contains four readable thumbnail resources with the conventional names and expected dimensions:

| Resource | Pixel size |
| --- | ---: |
| `thumbnail.png` | 90 × 58 |
| `thumbnail@2x.png` | 180 × 116 |
| `thumbnail@4x.png` | 360 × 232 |
| `thumbnail.tiff` | 90 × 58 |

The bundle smoke test now loads every representation and checks its exact pixel size. This catches missing, corrupt, renamed, or accidentally resampled assets before packaging.

A read-only runtime probe also asked macOS's own `ScreenSaverModule` object to load the currently installed App Mosaic bundle. It returned a non-null `NSImage` with a 90 × 58 logical size and identified all four resource URLs as its representations. This narrows the problem: the legacy screen-saver module loader can find and decode the artwork, so the observed generic library image is not explained by a missing or unreadable thumbnail.

For comparison, two newer installed third-party savers use a single larger `thumbnail.png` (432 × 278 and 480 × 312), while several older savers use `thumbnail.tiff` at 90 × 58, 180 × 116, or larger sizes. App Mosaic's naming, aspect ratio, and multi-resolution structure are therefore consistent with working bundles on this host. A larger base image may still be worth a controlled experiment, but current evidence does not justify presenting it as a fix.

Apple's public Screen Saver documentation describes the `.saver` bundle and says the system instantiates `ScreenSaverView` for previews, but does not document the static library-thumbnail filenames or cache behavior: <https://developer.apple.com/documentation/screensaver>.

## Next controlled check

When the display is awake and System Settings can be observed:

1. Record the installed bundle version, selected saver, and current library tile before changing anything.
2. Close System Settings, build a clean candidate, and install it through the existing backup-preserving installer only when that candidate has an intentionally incremented bundle version.
3. Reopen Screen Saver settings and record whether the tile changes before and after selecting App Mosaic and opening its preview.
4. In the same session, rerun the module-loader probe. If it still returns the correct image while the UI remains generic, treat the issue as System Settings presentation or caching rather than image packaging.
5. Avoid deleting broad system caches. Any cache experiment should resolve an exact file or process first and preserve a recoverable copy.

The installed saver and the v1.0.0 release were not replaced during this investigation.
