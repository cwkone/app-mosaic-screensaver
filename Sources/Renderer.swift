import AppKit
import QuartzCore

private final class MosaicCell {
    let layer = CALayer()
    var current = CALayer()
    var incoming = CALayer()
    init(size: Double, position: CGPoint, scale: Double) {
        layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        layer.position = position
        for image in [current, incoming] {
            image.frame = layer.bounds
            image.contentsGravity = .resizeAspect
            image.contentsScale = scale
            image.minificationFilter = .trilinear
            layer.addSublayer(image)
        }
        incoming.opacity = 0
    }
    func finish() {
        current.removeAllAnimations(); incoming.removeAllAnimations()
        current.contents = nil; current.opacity = 0
        incoming.opacity = 1
        swap(&current, &incoming)
    }
}

/// Texture-backed layers handle position and opacity. No full-grid frame loop.
final class MosaicRenderer {
    let root = CALayer()
    private let viewport = CALayer()
    private let emptyLabel = CATextLayer()
    private var cells: [MosaicCell] = []
    private var layout: MosaicLayout?
    private var playback: MosaicPlayback?
    private var apps: [String: InstalledApp] = [:]
    private var settings = MosaicSettings.defaults
    private var token = MosaicWorkToken()
    private var timer: Timer?
    private var active = false
    private var generation = 0
    private var ready = 0
    private var nextChange: Double = 0
    private var endings: [Int: (app: String, time: Double)] = [:]
    private var backingScale: Double = 1
    private(set) var eventCount = 0
    private(set) var rebuildCount = 0
    var cellCount: Int { cells.count }
    var readyCount: Int { ready }
    var running: Bool { active }
    var activeSwapCount: Int { playback?.activeCount ?? 0 }

    init() {
        root.backgroundColor = NSColor.black.cgColor
        root.isOpaque = true
        root.masksToBounds = true
        viewport.backgroundColor = NSColor.black.cgColor
        viewport.masksToBounds = true
        root.addSublayer(viewport)
        emptyLabel.fontSize = 13
        emptyLabel.alignmentMode = .center
        emptyLabel.foregroundColor = NSColor.secondaryLabelColor.cgColor
        root.addSublayer(emptyLabel)
    }
    private func withoutActions(_ body: () -> Void) {
        CATransaction.begin(); CATransaction.setDisableActions(true); body(); CATransaction.commit()
    }
    func configure(settings: MosaicSettings, apps: [InstalledApp], size: CGSize,
                   scale: Double, backingScale: Double, emptyMessage: String?) {
        generation += 1; rebuildCount += 1
        token.cancel(); token = MosaicWorkToken()
        timer?.invalidate(); timer = nil
        endings.removeAll(); ready = 0
        self.settings = settings; self.backingScale = backingScale
        self.apps = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        let geometry = MosaicLayout(settings: settings, width: size.width, height: size.height, scale: scale)
        layout = geometry
        playback = MosaicPlayback(settings: settings, apps: apps.map(\.id), count: geometry.count)
        withoutActions {
            root.bounds = CGRect(origin: .zero, size: size)
            viewport.frame = CGRect(x: geometry.margin, y: geometry.margin, width: geometry.width, height: geometry.height)
            viewport.sublayers = nil; cells.removeAll()
            emptyLabel.contentsScale = backingScale
            emptyLabel.frame = CGRect(x: 8, y: max(0, size.height / 2 - 12), width: max(0, size.width - 16), height: 25)
            emptyLabel.string = apps.isEmpty ? emptyMessage : nil
            for index in 0..<(playback?.slots.count ?? 0) {
                let point = geometry.position(index)
                let cell = MosaicCell(size: geometry.iconSize, position: CGPoint(x: point.x, y: point.y), scale: backingScale)
                cell.current.opacity = 0
                viewport.addSublayer(cell.layer); cells.append(cell)
            }
            addEdgeFade(geometry)
        }
        if active { addMotion() }
        let build = generation
        for (index, slot) in (playback?.slots ?? []).enumerated() {
            load(slot.app) { [weak self] image in
                guard let self, self.generation == build, self.cells.indices.contains(index) else { return }
                self.withoutActions {
                    self.cells[index].current.contents = image
                    self.cells[index].current.opacity = 1
                }
                self.ready += 1
                if self.ready == self.cells.count { self.beginScheduling() }
            }
        }
    }
    private func load(_ id: String, completion: @escaping (CGImage?) -> Void) {
        guard let app = apps[id], let layout else { completion(nil); return }
        MosaicArtworkCache.shared.request(app: app, pixels: Int(ceil(layout.iconSize * backingScale)),
            settings: settings, token: token, completion: completion)
    }
    func resume() {
        active = true
        addMotion()
        if ready == cells.count { beginScheduling() }
    }
    func stop() {
        active = false; generation += 1
        timer?.invalidate(); timer = nil
        token.cancel(); endings.removeAll()
        withoutActions { viewport.sublayers = nil; cells.removeAll(); emptyLabel.string = nil }
        playback = nil; ready = 0
    }
    private func addMotion() {
        guard let layout, settings.movement != .stationary else { return }
        let horizontal = settings.movement == .left || settings.movement == .right
        let increasing = settings.movement == .right || settings.movement == .up
        let span = horizontal ? layout.spanX : layout.spanY
        guard span > 0 else { return }
        let low = -layout.pitch / 2
        let high = low + span
        let duration = span / layout.pitch * settings.secondsPerCell
        let begin = CACurrentMediaTime()
        for (index, cell) in cells.enumerated() {
            let point = layout.position(index)
            let value = horizontal ? point.x : point.y
            let animation = CABasicAnimation(keyPath: horizontal ? "position.x" : "position.y")
            animation.fromValue = increasing ? low : high
            animation.toValue = increasing ? high : low
            animation.duration = duration
            animation.beginTime = cell.layer.convertTime(begin, from: nil)
            animation.timeOffset = (increasing ? value - low : high - value) / span * duration
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            cell.layer.add(animation, forKey: "drift")
        }
    }
    private func beginScheduling() {
        guard active, !cells.isEmpty, ready == cells.count else { return }
        nextChange = CACurrentMediaTime() + settings.changeInterval
        schedule()
    }
    private func schedule() {
        timer?.invalidate(); timer = nil
        guard active, !cells.isEmpty else { return }
        let now = CACurrentMediaTime()
        let nextEnd = endings.values.map(\.time).min() ?? .infinity
        let next = min(nextChange, nextEnd)
        timer = Timer(timeInterval: max(0.02, next - now), repeats: false) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    private func tick() {
        guard active else { return }
        eventCount += 1
        let now = CACurrentMediaTime()
        for (index, finish) in endings where finish.time <= now {
            withoutActions { cells[index].finish() }
            playback?.finish(index: index, app: finish.app, at: now)
            endings.removeValue(forKey: index)
        }
        if now >= nextChange {
            nextChange = now + settings.changeInterval * Double.random(in: 0.8...1.2)
            if let change = playback?.reserve(at: now) {
                let build = generation
                load(change.app) { [weak self] image in
                    guard let self, self.generation == build, self.active,
                          self.cells.indices.contains(change.index) else { return }
                    guard let image else {
                        self.playback?.cancel(index: change.index, app: change.app)
                        return
                    }
                    self.fade(index: change.index, to: image, app: change.app)
                }
            }
        }
        schedule()
    }
    private func fade(index: Int, to image: CGImage, app: String) {
        let cell = cells[index]
        let duration = settings.fadeDuration
        let begin = CACurrentMediaTime()
        withoutActions {
            cell.incoming.contents = image; cell.incoming.opacity = 1
            cell.current.opacity = 0
        }
        let outgoing = CABasicAnimation(keyPath: "opacity")
        outgoing.fromValue = 1; outgoing.toValue = 0
        outgoing.duration = duration; outgoing.beginTime = cell.current.convertTime(begin, from: nil)
        outgoing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cell.current.add(outgoing, forKey: "fadeOut")
        let incoming = CAKeyframeAnimation(keyPath: "opacity")
        incoming.values = [0, 0, 1]; incoming.keyTimes = [0, 0.5, 1]
        incoming.duration = duration * 2; incoming.beginTime = cell.incoming.convertTime(begin, from: nil)
        incoming.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeInEaseOut)]
        cell.incoming.add(incoming, forKey: "fadeIn")
        endings[index] = (app, begin + duration * 2)
        schedule()
    }
    private func addEdgeFade(_ layout: MosaicLayout) {
        let width = min(layout.width, layout.height) * settings.edgeFade
        guard width > 0 else { return }
        let clear = NSColor.black.withAlphaComponent(0).cgColor
        let black = NSColor.black.cgColor
        func strip(_ frame: CGRect, horizontal: Bool, reverse: Bool) {
            let gradient = CAGradientLayer()
            gradient.frame = frame
            gradient.colors = reverse ? [clear, black] : [black, clear]
            gradient.startPoint = horizontal ? CGPoint(x: 0, y: 0.5) : CGPoint(x: 0.5, y: 0)
            gradient.endPoint = horizontal ? CGPoint(x: 1, y: 0.5) : CGPoint(x: 0.5, y: 1)
            viewport.addSublayer(gradient)
        }
        strip(CGRect(x: 0, y: 0, width: width, height: layout.height), horizontal: true, reverse: false)
        strip(CGRect(x: layout.width - width, y: 0, width: width, height: layout.height), horizontal: true, reverse: true)
        strip(CGRect(x: 0, y: 0, width: layout.width, height: width), horizontal: false, reverse: false)
        strip(CGRect(x: 0, y: layout.height - width, width: layout.width, height: width), horizontal: false, reverse: true)
    }
    /// Export our own layer tree; no screen recording or desktop capture required.
    func snapshot() -> NSBitmapImageRep? {
        let width = max(1, Int(root.bounds.width)), height = max(1, Int(root.bounds.height))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        root.render(in: context.cgContext)
        return bitmap
    }
}
