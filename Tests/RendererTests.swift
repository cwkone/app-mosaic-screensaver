import AppKit
import QuartzCore

@main struct RendererTests {
    static func descendants(_ layer: CALayer) -> [CALayer] {
        [layer] + (layer.sublayers ?? []).flatMap(descendants)
    }
    static func waitReady(_ renderer: MosaicRenderer) {
        let deadline = Date().addingTimeInterval(30)
        while renderer.readyCount != renderer.cellCount && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(renderer.readyCount == renderer.cellCount)
    }
    static func main() {
        _ = NSApplication.shared
        let app = InstalledApp(id: "finder", name: "Finder", url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        let renderer = MosaicRenderer()
        let size = CGSize(width: 960, height: 540)
        for direction in MosaicSettings.Movement.allCases {
            var settings = MosaicSettings(); settings.iconSize = 64; settings.movement = direction
            renderer.configure(settings: settings, apps: [app], size: size, scale: 1, backingScale: 2, emptyMessage: nil)
            renderer.resume()
            let geometry = MosaicLayout(settings: settings, width: size.width, height: size.height)
            let horizontal = direction == .left || direction == .right
            let moving = direction != .stationary
            let layers = descendants(renderer.root)
            let drifting = layers.filter { $0.animation(forKey: "drift") != nil }
            precondition(drifting.count == (moving ? (horizontal ? geometry.columns : geometry.rows) : 0))
            // Every child retains the old per-cell motion phase at all times,
            // including both sides of the offscreen wrap boundary.
            for group in drifting {
                let animation = group.animation(forKey: "drift") as! CABasicAnimation
                let from = (animation.fromValue as! NSNumber).doubleValue
                let to = (animation.toValue as! NSNumber).doubleValue
                for cell in group.sublayers ?? [] {
                    let initial = group.position + cell.position
                    let index = (0..<geometry.count).first { index in
                        let point = geometry.position(index)
                        return abs(point.x - initial.x) < 0.001 && abs(point.y - initial.y) < 0.001
                    }!
                    for t in [0.0, 0.1, 7.99, 8.01, 100, 1000] {
                        let phase = ((t + animation.timeOffset) / animation.duration).truncatingRemainder(dividingBy: 1)
                        let value = from + (to - from) * phase
                        let expected = geometry.position(index, after: t, secondsPerCell: settings.secondsPerCell)
                        let span = horizontal ? geometry.spanX : geometry.spanY
                        let delta = abs(value - (horizontal ? expected.x : expected.y))
                        precondition(delta < 0.001 || abs(delta - span) < 0.001)
                    }
                }
            }
            waitReady(renderer)
            let rebuilds = renderer.rebuildCount, requests = MosaicArtworkCache.shared.requests
            renderer.configure(settings: settings, apps: [app], size: size, scale: 1, backingScale: 2, emptyMessage: "ignored")
            renderer.resume()
            precondition(renderer.rebuildCount == rebuilds && MosaicArtworkCache.shared.requests == requests)
            precondition(descendants(renderer.root).count == 3 + geometry.count + drifting.count)
            precondition(renderer.snapshot() != nil)
            renderer.stop()
            precondition(descendants(renderer.root).count == 3 && renderer.cellCount == 0 && !renderer.running)
        }
        // Cancellation followed immediately by reconfiguration cannot strand
        // readiness or allow obsolete callbacks to repopulate a stopped view.
        for index in 0..<20 {
            var settings = MosaicSettings(); settings.iconSize = Double(64 + index * 8)
            renderer.configure(settings: settings, apps: [app], size: size, scale: 1, backingScale: 1, emptyMessage: nil)
            renderer.stop()
        }
        var fast = MosaicSettings(); fast.frequency = 1; fast.fadeDuration = 0.2; fast.movement = .right
        let other = InstalledApp(id: "safari", name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))
        renderer.configure(settings: fast, apps: [app, other], size: size, scale: 1, backingScale: 1, emptyMessage: nil)
        renderer.resume(); waitReady(renderer)
        let base = descendants(renderer.root).count
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            precondition(descendants(renderer.root).count <= base + renderer.activeSwapCount)
        }
        precondition(renderer.eventCount > 0)
        renderer.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(renderer.cellCount == 0 && descendants(renderer.root).count == 3)
        print("PASS: grouped motion phases in all directions, dense layer counts, idempotent configure/resume, cancellation/restart, temporary fade layers, stop cleanup")
    }
}
private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
