import AppKit
import ScreenSaver

@main struct BundleSmoke {
    static func main() throws {
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let bundle = Bundle(url: url)!
        let expectedThumbnails = [
            ("thumbnail.png", 90, 58),
            ("thumbnail@2x.png", 180, 116),
            ("thumbnail@4x.png", 360, 232),
            ("thumbnail.tiff", 90, 58),
        ]
        guard let resources = bundle.resourceURL else { fatalError("Saver has no resource directory") }
        for (name, width, height) in expectedThumbnails {
            let thumbnailURL = resources.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: thumbnailURL),
                  let thumbnail = NSBitmapImageRep(data: data) else {
                fatalError("Cannot load bundled \(name)")
            }
            precondition(thumbnail.pixelsWide == width && thumbnail.pixelsHigh == height,
                         "Unexpected \(name) dimensions")
        }
        try bundle.loadAndReturnError()
        guard let viewClass = bundle.principalClass as? ScreenSaverView.Type,
              let view = viewClass.init(frame: NSRect(x: 0, y: 0, width: 640, height: 400), isPreview: true) else {
            fatalError("Cannot instantiate bundle principal class")
        }
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.startAnimation()
        let until = Date().addingTimeInterval(60)
        while Date() < until && !(view.value(forKey: "catalogReady") as! Bool) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05)); view.animateOneFrame()
        }
        precondition(view.value(forKey: "catalogReady") as! Bool)
        precondition((view.value(forKey: "discoveredAppCount") as! Int) > 0)
        view.setFrameSize(NSSize(width: 300, height: 600))
        view.animateOneFrame()
        let artworkDeadline = Date().addingTimeInterval(60)
        while Date() < artworkDeadline && !(view.value(forKey: "artworkReady") as! Bool) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        precondition(view.value(forKey: "artworkReady") as! Bool)
        let diagnostics = view.value(forKey: "renderingDiagnostics") as! NSDictionary
        for _ in 0..<10_000 { view.animateOneFrame() }
        precondition((view.value(forKey: "renderingDiagnostics") as! NSDictionary) == diagnostics)
        precondition(view.hasConfigureSheet)
        precondition(view.configureSheet != nil)
        view.stopAnimation()
        precondition(!view.isAnimating)
        view.setFrameSize(NSSize(width: 400, height: 300))
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        precondition((view.value(forKey: "renderingDiagnostics") as! NSDictionary)["cells"] as! Int == 0)
        view.startAnimation()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        precondition((view.value(forKey: "renderingDiagnostics") as! NSDictionary)["cells"] as! Int > 0)
        view.stopAnimation()
        if CommandLine.arguments.count > 2 {
            let app = URL(fileURLWithPath: CommandLine.arguments[2])
            let extensionURL = app.appendingPathComponent("Contents/Extensions/App Mosaic Focus Intents.appex")
            let extensionBundle = Bundle(url: extensionURL)!
            precondition(extensionBundle.bundleIdentifier == "one.cwk.AppMosaic.Preview.FocusIntents")
            precondition(extensionBundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "XPC!")
            let metadata = extensionURL.appendingPathComponent("Contents/Resources/Metadata.appintents/extract.actionsdata")
            let metadataData = try Data(contentsOf: metadata)
            let metadataText = String(decoding: metadataData, as: UTF8.self)
            precondition(metadataText.contains("SetMosaicPresetFocusFilter"))
            precondition(metadataText.contains("com.apple.link.systemProtocol.FocusConfiguration"))
            precondition(metadataText.contains("MosaicPresetEntityQuery"))
        }
        print("PASS: load actual .saver and thumbnail representations, instantiate principal class, discover, artwork ready, no frame rendering, configure sheet, stop/resize cleanup, restart, embedded Focus intent metadata")
    }
}
