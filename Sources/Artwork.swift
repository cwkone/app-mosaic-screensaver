import AppKit

final class MosaicWorkToken {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

private final class ArtworkJob {
    private let lock = NSLock()
    private var readers: [(MosaicWorkToken, (CGImage?) -> Void)] = []
    func add(_ token: MosaicWorkToken, _ callback: @escaping (CGImage?) -> Void) {
        lock.lock(); readers.append((token, callback)); lock.unlock()
    }
    var needed: Bool { lock.lock(); defer { lock.unlock() }; return readers.contains { !$0.0.isCancelled } }
    func deliver(_ image: CGImage?) {
        lock.lock(); let callbacks = readers; readers.removeAll(); lock.unlock()
        for (token, callback) in callbacks where !token.isCancelled { callback(image) }
    }
}

/// Immutable textures shared between saver instances. Disk access, rasterization,
/// transparent-padding trimming and tinting happen once, away from the main thread.
final class MosaicArtworkCache {
    static let shared = MosaicArtworkCache()
    private let cache = NSCache<NSString, CGImage>()
    // Preserve size-specific icon representations and normalization exactly;
    // reuse their uncolored pixels when only the palette changes.
    private let originals = NSCache<NSString, NSData>()
    private let workers = OperationQueue()
    private var pending: [String: ArtworkJob] = [:]
    private(set) var decodes = 0
    private(set) var normalizations = 0
    private(set) var requests = 0
    init() {
        cache.totalCostLimit = 48 * 1024 * 1024
        originals.totalCostLimit = 16 * 1024 * 1024
        workers.maxConcurrentOperationCount = 2
        workers.qualityOfService = .utility
    }
    func request(app: InstalledApp, pixels: Int, settings: MosaicSettings,
                 token: MosaicWorkToken, completion: @escaping (CGImage?) -> Void) {
        precondition(Thread.isMainThread)
        guard !token.isCancelled else { return }
        requests += 1
        let size = min(512, max(16, ((pixels + 7) / 8) * 8))
        let key = "\(app.artworkIdentity)|\(size)|\(settings.artworkKey)"
        if let image = cache.object(forKey: key as NSString) {
            if !token.isCancelled { completion(image) }
            return
        }
        if let job = pending[key], job.needed { job.add(token, completion); return }
        let job = ArtworkJob(); job.add(token, completion); pending[key] = job
        workers.addOperation {
            var normalized = false
            let image: CGImage? = autoreleasepool {
                guard job.needed else { return nil }
                let baseKey = "\(app.artworkIdentity)|\(size)" as NSString
                let original: NSData
                if let data = self.originals.object(forKey: baseKey) {
                    original = data
                } else {
                    let source = NSWorkspace.shared.icon(forFile: app.url.path)
                    guard job.needed else { return nil }
                    var rect = NSRect(x: 0, y: 0, width: size, height: size)
                    guard let cgImage = source.cgImage(forProposedRect: &rect, context: nil, hints: nil),
                          let bytes = MosaicImageProcessing.normalizedPixels(cgImage, pixels: size),
                          job.needed else { return nil }
                    original = Data(bytes) as NSData; normalized = true
                    self.originals.setObject(original, forKey: baseKey, cost: bytes.count)
                }
                guard job.needed else { return nil }
                let data = Data(referencing: original)
                if settings.colorMode == .original {
                    // Share the cached bytes with the texture's data provider.
                    return MosaicImageProcessing.image(data, size: size)
                }
                return MosaicImageProcessing.colorize(Array(data), pixels: size, settings: settings)
            }
            let didNormalize = normalized
            DispatchQueue.main.async {
                if didNormalize { self.normalizations += 1 }
                if let image {
                    self.decodes += 1
                    self.cache.setObject(image, forKey: key as NSString, cost: size * size * 4)
                }
                // A cancelled job can have been replaced while it was finishing.
                if self.pending[key] === job { self.pending.removeValue(forKey: key) }
                job.deliver(image)
            }
        }
    }
}

enum MosaicImageProcessing {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    static let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
    static func image(_ bytes: [UInt8], size: Int) -> CGImage? {
        image(Data(bytes), size: size)
    }
    static func image(_ data: Data, size: Int) -> CGImage? {
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: colorSpace, bitmapInfo: bitmapInfo, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
    static func raster(_ image: CGImage, size: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size * 4, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else { return }
            let ratio = min(Double(size) / Double(image.width), Double(size) / Double(image.height))
            let width = Double(image.width) * ratio, height = Double(image.height) * ratio
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: (Double(size) - width) / 2, y: (Double(size) - height) / 2,
                                          width: width, height: height))
        }
        return bytes
    }
    static func bodyBounds(_ bytes: [UInt8], size: Int) -> CGRect {
        func bounds(threshold: UInt8) -> CGRect? {
            var left = size, right = -1, top = size, bottom = -1
            for y in 0..<size {
                for x in 0..<size where bytes[(y * size + x) * 4 + 3] >= threshold {
                    left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
                }
            }
            guard right >= left else { return nil }
            let padding = max(1, Int(ceil(Double(max(right - left + 1, bottom - top + 1)) * 0.005)))
            left = max(0, left - padding); right = min(size - 1, right + padding)
            top = max(0, top - padding); bottom = min(size - 1, bottom + padding)
            return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        }
        return bounds(threshold: 128) ?? bounds(threshold: 8) ?? CGRect(x: 0, y: 0, width: size, height: size)
    }
    static func prepare(_ source: CGImage, pixels: Int, settings: MosaicSettings) -> CGImage? {
        guard let original = normalizedPixels(source, pixels: pixels) else { return nil }
        return colorize(original, pixels: pixels, settings: settings)
    }
    static func normalizedPixels(_ source: CGImage, pixels: Int) -> [UInt8]? {
        let analysisSize = max(128, pixels)
        let original = raster(source, size: analysisSize)
        guard let sample = image(original, size: analysisSize),
              let cropped = sample.cropping(to: bodyBounds(original, size: analysisSize)) else { return nil }
        return raster(cropped, size: pixels)
    }
    static func colorize(_ original: [UInt8], pixels: Int, settings: MosaicSettings) -> CGImage? {
        var output = original
        if settings.colorMode != .original {
            for offset in stride(from: 0, to: output.count, by: 4) {
                let alpha = Double(output[offset + 3]) / 255
                guard alpha > 0 else { continue }
                let red = Double(output[offset]) / alpha / 255
                let green = Double(output[offset + 1]) / alpha / 255
                let blue = Double(output[offset + 2]) / alpha / 255
                let luminance = min(1, max(0, red * 0.2126 + green * 0.7152 + blue * 0.0722))
                let sourceChannels = [red, green, blue]
                let tintChannels = [settings.tintRed, settings.tintGreen, settings.tintBlue]
                for channel in 0..<3 {
                    let result: Double
                    if settings.colorMode == .monochrome { result = luminance }
                    else {
                        let tinted = luminance * tintChannels[channel]
                        result = sourceChannels[channel] * (1 - settings.tintStrength) + tinted * settings.tintStrength
                    }
                    output[offset + channel] = UInt8(min(255, max(0, (result * alpha * 255).rounded())))
                }
            }
        }
        return image(output, size: pixels)
    }
}
