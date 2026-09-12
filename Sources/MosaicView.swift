import AppKit
import ScreenSaver
import os.log

@objc(AppMosaicView)
final class AppMosaicView: ScreenSaverView {
    static let settingsID = "one.cwk.AppMosaic"
    private let store = ScreenSaverDefaults(forModuleWithName: settingsID)!
    private var settings = MosaicSettings.defaults
    private var apps: [InstalledApp] = []
    private var loaded = false
    private var loading = false
    private var running = false
    private var renderAllowed = true
    private var sleeping = false
    private var options: MosaicOptionsController?
    private let renderer = MosaicRenderer()
    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private let log = OSLog(subsystem: settingsID, category: "screensaver")
    @objc var catalogReady: Bool { loaded }
    @objc var discoveredAppCount: Int { apps.count }
    @objc var artworkReady: Bool { loaded && renderer.readyCount == renderer.cellCount }
    @objc var renderingDiagnostics: NSDictionary {
        ["cells": renderer.cellCount, "ready": renderer.readyCount, "events": renderer.eventCount,
         "rebuilds": renderer.rebuildCount, "decodes": MosaicArtworkCache.shared.decodes,
         "requests": MosaicArtworkCache.shared.requests, "activeSwaps": renderer.activeSwapCount,
         "running": renderer.running]
    }
    var discoveredApps: [InstalledApp] { apps }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview); initialize()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); initialize() }
    private func initialize() {
        // The host can call animateOneFrame, but the compositor owns animation.
        animationTimeInterval = 1
        settings = MosaicSettings(store: store)
        layer = renderer.root
        wantsLayer = true
        for name in ["com.apple.screensaver.willstop", "com.apple.screensaver.didstop"] {
            distributedObservers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.stopAnimation() })
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = true; self?.renderer.stop()
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sleeping = false
            if self.running, self.window != nil { self.rebuild() }
        })
    }
    deinit {
        for observer in distributedObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    private func discover() {
        guard !loading else { return }
        loading = true
        SharedAppCatalog.shared.request { [weak self] apps in
            guard let self else { return }
            let changed = !self.loaded || self.apps != apps
            self.apps = apps; self.loaded = true; self.loading = false
            self.options?.updateApps(apps)
            if changed, self.window != nil, !self.sleeping { self.rebuild() }
            os_log("Discovered %d apps", log: self.log, type: .info, apps.count)
        }
    }
    private func rebuild() {
        guard window != nil, !sleeping, renderAllowed else { return }
        let included = apps.filter { !settings.excludedApps.contains($0.id) }
        let miniature = isPreview || bounds.width < 600
        let screenSize = window?.screen?.frame.size ?? NSSize(width: 1920, height: 1080)
        let scale = miniature ? min(1, min(bounds.width / max(800, screenSize.width), bounds.height / max(600, screenSize.height))) : 1
        let message = !loaded ? "Finding your apps…" : apps.isEmpty ? "No apps found" : "No apps selected"
        renderer.configure(settings: settings, apps: included, size: bounds.size, scale: scale,
                           backingScale: Double(window?.backingScaleFactor ?? 1), emptyMessage: miniature ? message : nil)
        if running && !renderer.running { renderer.resume() }
    }
    override var isOpaque: Bool { true }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if loaded { rebuild() }
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if loaded { rebuild() }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopAnimation() }
        else { renderAllowed = true; rebuild(); discover() }
    }
    override func startAnimation() {
        running = true; renderAllowed = true
        store.synchronize(); settings = MosaicSettings(store: store)
        super.startAnimation()
        rebuild(); discover()
        os_log("Layer animation started", log: log, type: .info)
    }
    override func stopAnimation() {
        running = false; renderAllowed = false
        renderer.stop()
        super.stopAnimation()
        os_log("Layer animation stopped", log: log, type: .info)
    }
    override func animateOneFrame() { /* Core Animation does not need CPU frame callbacks. */ }
    override var hasConfigureSheet: Bool { true }
    override var configureSheet: NSWindow? {
        store.synchronize()
        let controller = MosaicOptionsController(settings: MosaicSettings(store: store), apps: apps) { [weak self] settings in
            guard let self else { return }
            settings.save(to: self.store); self.settings = settings; self.rebuild()
        }
        options = controller
        return controller.window
    }
    func snapshot() -> NSBitmapImageRep? { renderer.snapshot() }
    /// Preview configurations without saving or changing the user's exclusions.
    func preview(_ settings: MosaicSettings) { self.settings = settings; rebuild() }
}
