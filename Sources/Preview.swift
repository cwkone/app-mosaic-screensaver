import AppKit
import ScreenSaver
import Darwin

@main
struct PreviewMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = PreviewDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var saver: AppMosaicView!
    private var verificationAttempts = 0
    private var verificationConfigured = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit App Mosaic Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem(); item.submenu = appMenu; menu.addItem(item); NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 740),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "App Mosaic Preview"
        window.minSize = NSSize(width: 640, height: 440)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 740))
        saver = AppMosaicView(frame: NSRect(x: 0, y: 54, width: 1100, height: 686), isPreview: false)!
        saver.autoresizingMask = [.width, .height]
        root.addSubview(saver)
        let text = NSTextField(labelWithString: "App Mosaic")
        text.font = .systemFont(ofSize: 13, weight: .semibold); text.frame = NSRect(x: 20, y: 18, width: 200, height: 20)
        root.addSubview(text)
        let options = NSButton(title: "Screen Saver Options…", target: self, action: #selector(showOptions))
        options.bezelStyle = .rounded; options.frame = NSRect(x: 871, y: 11, width: 211, height: 32)
        options.autoresizingMask = [.minXMargin]; root.addSubview(options)
        window.contentView = root; window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        saver.startAnimation()
        if CommandLine.arguments.contains("--verify") {
            Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in self.verify() }
        }
    }
    @objc private func showOptions() { if let sheet = saver.configureSheet { window.beginSheet(sheet) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { saver.stopAnimation() }

    private func snapshot(_ view: NSView, name: String) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.75))
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        let bitmap: NSBitmapImageRep
        if let saver = view as? AppMosaicView {
            print("Snapshot \(name): \(saver.renderingDiagnostics)")
            guard let image = saver.snapshot() else { fatalError("Layer snapshot failed") }; bitmap = image
            var visiblePixels = 0
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                       max(color.redComponent, color.greenComponent, color.blueComponent) > 0.05 {
                        visiblePixels += 1
                    }
                }
            }
            verifyCheck(visiblePixels > bitmap.pixelsWide * bitmap.pixelsHigh / 640, "\(name) contains no visible grid")
        } else {
            guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Snapshot failed") }
            view.cacheDisplay(in: view.bounds, to: image); bitmap = image
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG failed") }
        try! data.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/QA/" + name + ".png"))
    }
    private func verifyCheck(_ condition: @autoclosure () -> Bool, _ message: String = "", line: Int = #line) {
        if !condition() {
            FileHandle.standardError.write(Data("FAIL preview line \(line): \(message)\n".utf8))
            exit(1)
        }
    }
    private func verify() {
        if saver.catalogReady && !verificationConfigured {
            verificationConfigured = true
            window.setContentSize(NSSize(width: 1280, height: 774))
            saver.preview(.defaults)
        }
        guard saver.catalogReady && saver.artworkReady else {
            verificationAttempts += 1
            verifyCheck(verificationAttempts < 120, "Discovery timed out")
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in self.verify() }
            return
        }
        func awaitArtwork() {
            let deadline = Date().addingTimeInterval(60)
            while !saver.artworkReady && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            verifyCheck(saver.artworkReady)
        }
        let apps = saver.discoveredApps
        verifyCheck(!apps.isEmpty, "App discovery failed")
        snapshot(saver, name: "grid")
        window.setContentSize(NSSize(width: 1920, height: 1134))
        awaitArtwork()
        let diagnostics = saver.renderingDiagnostics
        for _ in 0..<10_000 { saver.animateOneFrame() }
        verifyCheck(saver.renderingDiagnostics == diagnostics, "Frame callbacks must not render or request icons")
        func cpu() -> Double {
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
        }
        FileHandle.standardError.write(Data("Measuring layer renderer with warm textures…\n".utf8))
        let cpuStart = cpu()
        RunLoop.main.run(until: Date().addingTimeInterval(10))
        let cpuSeconds = cpu() - cpuStart
        let result = "Layer preview, warm textures, 1920x1080, 10 seconds: \(cpuSeconds) process CPU seconds. Events: \(saver.renderingDiagnostics). Excludes WindowServer/GPU cost; displays may be asleep."
        print(result)
        try! result.write(toFile: FileManager.default.currentDirectoryPath + "/QA/layer-performance.txt", atomically: true, encoding: .utf8)
        window.setContentSize(NSSize(width: 1280, height: 774))
        awaitArtwork()
        var appearance = MosaicSettings()
        appearance.edgeFade = 0.18; appearance.movement = .left
        saver.preview(appearance); awaitArtwork(); snapshot(saver, name: "grid-edge-fade")
        appearance.edgeFade = 0; appearance.colorMode = .tinted
        saver.preview(appearance); awaitArtwork(); snapshot(saver, name: "grid-tinted")
        appearance.colorMode = .monochrome
        saver.preview(appearance); awaitArtwork(); snapshot(saver, name: "grid-monochrome")
        saver.preview(.defaults); awaitArtwork()
        var saved: MosaicSettings?
        let controller = MosaicOptionsController(settings: .defaults, apps: apps) { saved = $0 }
        window.beginSheet(controller.window)
        snapshot(controller.window.contentView!, name: "options")
        let tabs = controller.window.contentView!.subviews.compactMap { $0 as? NSTabView }.first!
        verifyCheck(tabs.numberOfTabViewItems == 3)
        func controls<T: NSView>(_ type: T.Type) -> [T] {
            tabs.tabViewItems.flatMap { $0.view?.subviews.compactMap { $0 as? T } ?? [] }
        }
        let allSliders = controls(NSSlider.self)
        verifyCheck(allSliders.count == 8)
        let spacing = allSliders.first { $0.identifier?.rawValue == "spacing" }!
        spacing.doubleValue = 0.3
        NSApp.sendAction(spacing.action!, to: spacing.target, from: spacing)
        verifyCheck(abs(controller.draft.spacing - 0.3) < 0.0001)
        let colorMode = controls(NSPopUpButton.self).first { $0.itemTitles.contains("Tinted") }!
        colorMode.selectItem(withTitle: "Tinted")
        NSApp.sendAction(colorMode.action!, to: colorMode.target, from: colorMode)
        verifyCheck(controller.draft.colorMode == .tinted && controls(NSColorWell.self).first!.isEnabled)
        tabs.selectTabViewItem(at: 1); snapshot(controller.window.contentView!, name: "options-animation")
        tabs.selectTabViewItem(at: 2); snapshot(controller.window.contentView!, name: "options-appearance")
        controller.excludeAll()
        verifyCheck(controller.draft.excludedApps.count == apps.count)
        controller.includeAll()
        verifyCheck(controller.draft.excludedApps.isEmpty)
        controller.excludeAll()
        controller.restoreDefaults()
        verifyCheck(controller.draft == .defaults)
        controller.showChooser()
        if let chooser = controller.window.attachedSheet {
            snapshot(chooser.contentView!, name: "choose-apps")
            let field = chooser.contentView!.subviews.compactMap { $0 as? NSSearchField }.first!
            field.stringValue = "Safari"
            controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            let scroll = chooser.contentView!.subviews.compactMap { $0 as? NSScrollView }.first!
            let table = scroll.documentView as! NSTableView
            let matches = apps.filter { $0.name.localizedCaseInsensitiveContains("Safari") }
            verifyCheck(table.numberOfRows == matches.count && !matches.isEmpty)
            let row = controller.tableView(table, viewFor: table.tableColumns[0], row: 0)!
            let checkbox = row.subviews.compactMap { $0 as? NSButton }.first!
            checkbox.performClick(nil)
            verifyCheck(controller.draft.excludedApps.contains(matches[0].id))
            checkbox.performClick(nil)
            verifyCheck(!controller.draft.excludedApps.contains(matches[0].id))
            controller.closeChooser()
        } else { fatalError("Choose Apps sheet did not open") }
        controller.save()
        verifyCheck(saved == .defaults)
        var cancelledSaved = false
        let cancelled = MosaicOptionsController(settings: .defaults, apps: apps) { _ in cancelledSaved = true }
        window.beginSheet(cancelled.window)
        cancelled.excludeAll()
        cancelled.cancel()
        verifyCheck(!cancelledSaved)
        saver.stopAnimation()
        verifyCheck((saver.renderingDiagnostics["cells"] as! Int) == 0)
        verifyCheck((saver.renderingDiagnostics["running"] as! Bool) == false)
        print("PASS: preview, discovery (\(apps.count) apps), options, choose apps, include/exclude all, restore defaults, search, individual checkboxes, new layout/color controls, no per-frame rendering, stop cleanup, cancel, save callback, appearance snapshots")
        NSApp.terminate(nil)
    }
}
