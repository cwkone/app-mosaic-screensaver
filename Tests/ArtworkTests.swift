import AppKit

@main struct ArtworkTests {
    static func check(_ value: @autoclosure () -> Bool, _ message: String = "", line: Int = #line) {
        if !value() {
            FileHandle.standardError.write(Data("FAIL artwork line \(line): \(message)\n".utf8))
            exit(1)
        }
    }
    static func main() {
        let size = 64
        var source = [UInt8](repeating: 0, count: size * size * 4)
        for y in 16..<48 {
            for x in 16..<48 {
                let dx = max(0, max(22 - x, x - 41))
                let dy = max(0, max(22 - y, y - 41))
                if dx * dx + dy * dy > 36 { continue }
                let offset = (y * size + x) * 4
                source[offset] = x < 32 ? 255 : 0
                source[offset + 1] = x < 32 ? 0 : 255
                source[offset + 3] = 255
            }
        }
        let image = MosaicImageProcessing.image(source, size: size)!
        let original = MosaicImageProcessing.prepare(image, pixels: 64, settings: .defaults)!
        let pixels = MosaicImageProcessing.raster(original, size: size)
        let normalized = MosaicImageProcessing.bodyBounds(pixels, size: size)
        check(normalized.width > 56 && normalized.height > 56, "Empty icon canvas wasn't normalized")
        check(pixels[3] == 0, "Transparency must be preserved")
        var config = MosaicSettings(); config.colorMode = .monochrome
        let gray = MosaicImageProcessing.raster(MosaicImageProcessing.prepare(image, pixels: 64, settings: config)!, size: size)
        for offset in stride(from: 0, to: gray.count, by: 4) {
            check(gray[offset] == gray[offset + 1] && gray[offset + 1] == gray[offset + 2])
            check(gray[offset + 3] == pixels[offset + 3])
        }
        config.colorMode = .tinted; config.tintRed = 0; config.tintGreen = 0; config.tintBlue = 1
        let tinted = MosaicImageProcessing.raster(MosaicImageProcessing.prepare(image, pixels: 64, settings: config)!, size: size)
        check(tinted.enumerated().contains { $0.offset % 4 == 2 && $0.element > 0 })
        for offset in stride(from: 0, to: tinted.count, by: 4) {
            check(tinted[offset] == 0 && tinted[offset + 1] == 0)
            check(tinted[offset + 3] == pixels[offset + 3])
        }
        config.tintStrength = 0
        let noTint = MosaicImageProcessing.raster(MosaicImageProcessing.prepare(image, pixels: 64, settings: config)!, size: size)
        check(noTint == pixels)
        let transparent = MosaicImageProcessing.image([UInt8](repeating: 0, count: size * size * 4), size: size)!
        check(MosaicImageProcessing.prepare(transparent, pixels: 64, settings: .defaults) != nil)
        let token = MosaicWorkToken(); check(!token.isCancelled); token.cancel(); check(token.isCancelled)
        let cache = MosaicArtworkCache()
        var app = InstalledApp(id: "finder", name: "Finder", url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        func request(_ settings: MosaicSettings, pixels: Int = 64) {
            var done = false
            cache.request(app: app, pixels: pixels, settings: settings, token: MosaicWorkToken()) { image in
                check(image != nil); done = true
            }
            let deadline = Date().addingTimeInterval(20)
            while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            check(done, "cache completion timeout")
        }
        request(.defaults)
        check(cache.normalizations == 1)
        config.colorMode = .monochrome; request(config)
        config.colorMode = .tinted; request(config)
        check(cache.normalizations == 1, "palette variants must share uncolored pixels")
        request(.defaults, pixels: 128)
        check(cache.normalizations == 2, "preserve size-specific artwork representations")
        app.modifiedAt = Date(timeIntervalSince1970: 1234)
        request(.defaults)
        check(cache.normalizations == 3, "updated applications must invalidate artwork")
        let cancelled = MosaicWorkToken(); cancelled.cancel()
        let previous = cache.requests
        cache.request(app: app, pixels: 64, settings: .defaults, token: cancelled) { _ in
            fatalError("cancelled request was delivered")
        }
        check(cache.requests == previous)
        print("PASS: transparent padding, alpha preservation, monochrome, tint hue/strength, empty images, work cancellation, palette reuse, size fidelity, app-update invalidation")
    }
}
