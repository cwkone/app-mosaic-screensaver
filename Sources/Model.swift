import Foundation

struct MosaicSettings: Equatable {
    enum Movement: Int, CaseIterable {
        case stationary, left, right, up, down
        var title: String { ["Stationary", "Left", "Right", "Up", "Down"][rawValue] }
    }
    enum ScreenEdges: Int, CaseIterable {
        case fill, wholeIcons
        var title: String { ["Fill the screen", "Keep whole icons"][rawValue] }
    }
    enum ColorMode: Int, CaseIterable {
        case original, monochrome, tinted
        var title: String { ["Original", "Monochrome", "Tinted"][rawValue] }
    }
    var iconSize: Double = 104
    var spacing: Double = 0.08
    var screenEdges: ScreenEdges = .fill
    var edgeMargin: Double = 0
    var edgeFade: Double = 0
    var frequency: Double = log(2.59 / 30) / log(0.25 / 30)
    var fadeDuration: Double = 1.5
    var movement: Movement = .stationary
    var scrollSpeed: Double = log(52.0 / 240) / log(8.0 / 240)
    var colorMode: ColorMode = .original
    var tintRed: Double = 0.39
    var tintGreen: Double = 0.82
    var tintBlue: Double = 1
    var tintStrength: Double = 1
    var excludedApps: Set<String> = []
    static let defaults = MosaicSettings()
    var changeInterval: Double { 30 * pow(0.25 / 30, frequency) }
    var secondsPerCell: Double { 240 * pow(8.0 / 240, scrollSpeed) }
    var minimumHold: Double { min(8, max(0.5, changeInterval * 2)) }
    var artworkKey: String {
        guard colorMode != .original else { return "original" }
        if colorMode == .monochrome { return "monochrome" }
        return "tint-\(Int(tintRed * 255))-\(Int(tintGreen * 255))-\(Int(tintBlue * 255))-\(Int(tintStrength * 100))"
    }

    init() {}
    init(store: UserDefaults) {
        func number(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            guard let value = store.object(forKey: key) as? NSNumber, value.doubleValue.isFinite else { return fallback }
            return min(range.upperBound, max(range.lowerBound, value.doubleValue))
        }
        iconSize = number("iconSize", 104, 64...256)
        spacing = number("spacing", 0.08, 0...0.6)
        screenEdges = ScreenEdges(rawValue: store.integer(forKey: "screenEdges")) ?? .fill
        edgeMargin = number("edgeMargin", 0, 0...0.15)
        edgeFade = number("edgeFade", 0, 0...0.3)
        fadeDuration = number("fadeDuration", 1.5, 0.2...10)
        movement = Movement(rawValue: store.integer(forKey: "movement")) ?? .stationary
        frequency = number("frequency", frequency, 0...1)
        scrollSpeed = number("scrollSpeed", scrollSpeed, 0...1)
        // Keep the user's old timing and exclusions when widening the sliders.
        if store.integer(forKey: "settingsVersion") < 2 {
            if store.object(forKey: "frequency") != nil {
                frequency = log((3.4 - frequency * 2.7) / 30) / log(0.25 / 30)
            }
            if store.object(forKey: "scrollSpeed") != nil {
                scrollSpeed = log((60 - scrollSpeed * 40) / 240) / log(8.0 / 240)
            }
        }
        colorMode = ColorMode(rawValue: store.integer(forKey: "colorMode")) ?? .original
        tintRed = number("tintRed", 0.39, 0...1)
        tintGreen = number("tintGreen", 0.82, 0...1)
        tintBlue = number("tintBlue", 1, 0...1)
        tintStrength = number("tintStrength", 1, 0...1)
        excludedApps = Set(store.stringArray(forKey: "excludedApps") ?? [])
    }
    func save(to store: UserDefaults) {
        let numbers: [String: Double] = ["iconSize": iconSize, "spacing": spacing, "edgeMargin": edgeMargin,
            "edgeFade": edgeFade, "frequency": frequency, "fadeDuration": fadeDuration, "scrollSpeed": scrollSpeed,
            "tintRed": tintRed, "tintGreen": tintGreen, "tintBlue": tintBlue, "tintStrength": tintStrength]
        for (key, value) in numbers { store.set(value, forKey: key) }
        store.set(screenEdges.rawValue, forKey: "screenEdges")
        store.set(movement.rawValue, forKey: "movement")
        store.set(colorMode.rawValue, forKey: "colorMode")
        store.set(excludedApps.sorted(), forKey: "excludedApps")
        store.set(2, forKey: "settingsVersion")
        store.synchronize()
    }
}

struct AppRotation {
    private(set) var pool: [String]
    private var remaining: [String] = []
    init(_ pool: [String]) { self.pool = Array(Set(pool)).sorted() }
    mutating func next(avoiding visible: Set<String>, current: String? = nil) -> String? {
        guard !pool.isEmpty else { return nil }
        if remaining.isEmpty { remaining = pool.shuffled() }
        if let index = remaining.firstIndex(where: { !visible.contains($0) && $0 != current }) {
            remaining.swapAt(index, remaining.count - 1)
            return remaining.removeLast()
        }
        // Reservoir sampling keeps fallback selection uniform without allocating
        // temporary arrays when the grid is larger than the installed collection.
        func choose(_ eligible: (String) -> Bool) -> String? {
            var result: String?, count = 0
            for app in pool where eligible(app) {
                count += 1
                if Int.random(in: 0..<count) == 0 { result = app }
            }
            return result
        }
        if let next = choose({ !visible.contains($0) && $0 != current }) { return next }
        guard pool.count > 1, let current, let index = pool.firstIndex(of: current) else { return pool.randomElement() }
        let choice = Int.random(in: 0..<(pool.count - 1))
        return pool[choice >= index ? choice + 1 : choice]
    }
}

struct MosaicLayout {
    let width: Double
    let height: Double
    let margin: Double
    let iconSize: Double
    let pitch: Double
    let columns: Int
    let rows: Int
    let originX: Double
    let originY: Double
    let movement: MosaicSettings.Movement
    var spanX: Double { Double(columns) * pitch }
    var spanY: Double { Double(rows) * pitch }
    var count: Int { columns * rows }
    var inset: Double { (pitch - iconSize) / 2 }
    init(settings: MosaicSettings, width: Double, height: Double, scale: Double = 1) {
        self.margin = min(width, height) * settings.edgeMargin
        self.width = max(0, width - margin * 2)
        self.height = max(0, height - margin * 2)
        iconSize = max(1, settings.iconSize * max(0.02, scale))
        let cellPitch = iconSize * (1 + settings.spacing)
        pitch = cellPitch
        movement = settings.movement
        let horizontal = movement == .left || movement == .right
        let vertical = movement == .up || movement == .down
        let fill = settings.screenEdges == .fill
        func cells(_ length: Double, moving: Bool) -> Int {
            guard length > 0 else { return 0 }
            if moving { return max(1, Int(ceil(length / cellPitch))) + 2 }
            return fill ? max(1, Int(ceil(length / cellPitch))) : max(1, Int(floor(length / cellPitch)))
        }
        columns = cells(self.width, moving: horizontal)
        rows = cells(self.height, moving: vertical)
        originX = horizontal ? -pitch : (self.width - Double(columns) * pitch) / 2
        originY = vertical ? -pitch : (self.height - Double(rows) * pitch) / 2
    }
    func position(_ index: Int) -> (x: Double, y: Double) {
        (originX + Double(index % max(1, columns)) * pitch + pitch / 2,
         originY + Double(index / max(1, columns)) * pitch + pitch / 2)
    }
    /// Periodic movement whose only discontinuity is fully outside the viewport.
    func position(_ index: Int, after seconds: Double, secondsPerCell: Double) -> (x: Double, y: Double) {
        var p = position(index)
        let distance = pitch / secondsPerCell * seconds
        func wrap(_ value: Double, low: Double, span: Double) -> Double {
            guard span > 0 else { return value }
            return low + ((value - low).truncatingRemainder(dividingBy: span) + span).truncatingRemainder(dividingBy: span)
        }
        switch movement {
        case .stationary: break
        case .left: p.x = wrap(p.x - distance, low: originX + pitch / 2, span: spanX)
        case .right: p.x = wrap(p.x + distance, low: originX + pitch / 2, span: spanX)
        case .up: p.y = wrap(p.y + distance, low: originY + pitch / 2, span: spanY)
        case .down: p.y = wrap(p.y - distance, low: originY + pitch / 2, span: spanY)
        }
        return p
    }
}

struct MosaicSlot {
    var app: String
    var replacement: String?
    var lastChange: Double = -.infinity
}

/// Discrete app changes only. Core Animation handles the frames between events.
struct MosaicPlayback {
    private(set) var slots: [MosaicSlot] = []
    private var rotation: AppRotation
    let settings: MosaicSettings
    var activeCount: Int { slots.reduce(0) { $0 + ($1.replacement == nil ? 0 : 1) } }
    var maximumActive: Int { max(1, Int(ceil(Double(slots.count) * 0.12))) }
    init(settings: MosaicSettings, apps: [String], count: Int) {
        self.settings = settings
        rotation = AppRotation(apps)
        var used: Set<String> = []
        for _ in 0..<max(0, count) {
            guard let app = rotation.next(avoiding: used) else { break }
            used.insert(app); slots.append(MosaicSlot(app: app))
        }
    }
    mutating func reserve(at time: Double) -> (index: Int, app: String)? {
        guard rotation.pool.count > 1, activeCount < maximumActive else { return nil }
        let eligible = slots.indices.filter { slots[$0].replacement == nil && time - slots[$0].lastChange >= settings.minimumHold }
        guard let index = eligible.randomElement() else { return nil }
        let visible = Set(slots.map(\.app) + slots.compactMap(\.replacement))
        guard let app = rotation.next(avoiding: visible, current: slots[index].app), app != slots[index].app else { return nil }
        slots[index].replacement = app
        return (index, app)
    }
    mutating func cancel(index: Int, app: String) {
        guard slots.indices.contains(index), slots[index].replacement == app else { return }
        slots[index].replacement = nil
    }
    mutating func finish(index: Int, app: String, at time: Double) {
        guard slots.indices.contains(index), slots[index].replacement == app else { return }
        slots[index].app = app; slots[index].replacement = nil; slots[index].lastChange = time
    }
}
