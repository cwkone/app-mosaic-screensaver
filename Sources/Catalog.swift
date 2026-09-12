import AppKit
import Darwin

struct InstalledApp: Equatable {
    let id: String
    let name: String
    let url: URL
    var modifiedAt: Date? = nil
    var artworkIdentity: String { "\(url.path)|\(modifiedAt?.timeIntervalSince1970 ?? 0)" }
}

enum AppCatalog {
    static var roots: [URL] {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return [home + "/Applications", "/Applications", "/System/Applications", "/System/Library/CoreServices/Applications"].map { URL(fileURLWithPath: $0) }
    }
    static func discover(in directories: [URL] = roots) -> [InstalledApp] {
        let manager = FileManager.default
        var found: [String: InstalledApp] = [:]
        func add(_ url: URL) {
            guard let bundle = Bundle(url: url) else { return }
            let info = bundle.infoDictionary ?? [:]
            // Exclude background agents and helpers rather than exposing internals.
            if (info["LSBackgroundOnly"] as? NSNumber)?.boolValue == true { return }
            let id = bundle.bundleIdentifier ?? url.standardizedFileURL.path
            guard found[id] == nil else { return }
            let name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String) ??
                (info["CFBundleDisplayName"] as? String) ??
                url.deletingPathExtension().lastPathComponent
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            found[id] = InstalledApp(id: id, name: name, url: url, modifiedAt: modified)
        }
        // App collections can contain SDKs with millions of source/resource
        // files (for example Unreal Engine). Only walk directories where an
        // installed, launchable app is plausible; never walk app internals.
        let ignoredFolders: Set<String> = ["node_modules", "source", "src", "include", "resources", "contents",
            "frameworks", "assets", "content", "intermediate", "deriveddata", "saved", "thirdparty",
            "thirdpartynotue", "tests", "test", "examples", "samples", "documentation", "docs",
            "site-packages", "__pycache__", "venv"]
        let ignoredPackages: Set<String> = ["framework", "bundle", "plugin", "kext", "pkg", "photoslibrary"]
        for root in directories {
            var pending: [(URL, Int)] = [(root, 0)]
            while let (folder, depth) = pending.popLast() {
                guard let entries = try? manager.contentsOfDirectory(at: folder,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { continue }
                for url in entries {
                    if url.pathExtension.lowercased() == "app" { add(url); continue }
                    guard depth < 6, !ignoredFolders.contains(url.lastPathComponent.lowercased()),
                          !ignoredPackages.contains(url.pathExtension.lowercased()),
                          let info = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                          info.isDirectory == true, info.isSymbolicLink != true else { continue }
                    pending.append((url, depth + 1))
                }
            }
        }
        if directories == roots { add(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")) }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

final class IconCache {
    private let images = NSCache<NSString, NSImage>()
    init() { images.totalCostLimit = 48 * 1024 * 1024; images.countLimit = 512 }
    func image(for app: InstalledApp, pixels: Int = 64) -> NSImage {
        let key = "\(app.id):\(pixels)" as NSString
        if let image = images.object(forKey: key) { return image }
        let source = NSWorkspace.shared.icon(forFile: app.url.path)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return source }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.addRepresentation(bitmap)
        images.setObject(image, forKey: key, cost: pixels * pixels * 4)
        return image
    }
    func clear() { images.removeAllObjects() }
}

/// Reuse the last local catalog immediately, refreshing it in the background.
/// A small persisted snapshot avoids rescanning before the first visible icon.
final class SharedAppCatalog {
    static let shared = SharedAppCatalog()
    private let snapshotStore = UserDefaults(suiteName: "one.cwk.AppMosaic.Catalog")!
    private var cached: [InstalledApp] = []
    private var scannedAt = Date.distantPast
    private var waiting: [(needsInitial: Bool, callback: ([InstalledApp]) -> Void)] = []
    private var scanning = false
    init() {
        var seen: Set<String> = []
        let records = snapshotStore.array(forKey: "apps") as? [[String: String]] ?? []
        cached = records.compactMap { record in
            guard let id = record["id"], !id.isEmpty, let name = record["name"], !name.isEmpty,
                  let path = record["path"], path.hasPrefix("/"), !seen.contains(id) else { return nil }
            let url = URL(fileURLWithPath: path)
            guard url.pathExtension.lowercased() == "app" else { return nil }
            seen.insert(id)
            return InstalledApp(id: id, name: name, url: url, modifiedAt: record["modifiedAt"].flatMap(Double.init).map(Date.init(timeIntervalSince1970:)))
        }
        if let date = snapshotStore.object(forKey: "scannedAt") as? Date { scannedAt = date }
    }
    func request(_ completion: @escaping ([InstalledApp]) -> Void) {
        precondition(Thread.isMainThread)
        let needsInitial = cached.isEmpty
        if !needsInitial { completion(cached) }
        if !needsInitial && Date().timeIntervalSince(scannedAt) < 30 { return }
        waiting.append((needsInitial, completion))
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async {
            let apps = AppCatalog.discover()
            DispatchQueue.main.async {
                let result = apps.isEmpty && !self.cached.isEmpty ? self.cached : apps
                let changed = result != self.cached
                self.cached = result; self.scannedAt = Date(); self.scanning = false
                if changed {
                    self.snapshotStore.set(result.map { ["id": $0.id, "name": $0.name, "path": $0.url.path,
                        "modifiedAt": String($0.modifiedAt?.timeIntervalSince1970 ?? 0)] }, forKey: "apps")
                }
                self.snapshotStore.set(self.scannedAt, forKey: "scannedAt")
                self.snapshotStore.synchronize()
                let callbacks = self.waiting; self.waiting.removeAll()
                for waiter in callbacks where waiter.needsInitial || changed { waiter.callback(result) }
            }
        }
    }
}
