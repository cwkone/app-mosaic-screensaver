import AppKit
import QuartzCore
import Darwin

/// Offscreen, same-process renderer probe. Does not measure GPU/WindowServer.
@main struct PerformanceProbe {
    static func cpu() -> Double {
        var r = rusage(); getrusage(RUSAGE_SELF, &r)
        return Double(r.ru_utime.tv_sec + r.ru_stime.tv_sec) + Double(r.ru_utime.tv_usec + r.ru_stime.tv_usec) / 1e6
    }
    static func tree(_ layer: CALayer) -> (Int, Int) {
        (layer.sublayers ?? []).reduce((1, layer.animationKeys()?.count ?? 0)) { total, child in
            let sub = tree(child); return (total.0 + sub.0, total.1 + sub.1)
        }
    }
    static func main() {
        _ = NSApplication.shared
        let mode = CommandLine.arguments.dropFirst().first ?? "dense"
        let apps = AppCatalog.discover()
        let selected = mode == "tiny" ? Array(apps.prefix(2)) : apps
        var settings = MosaicSettings(); settings.iconSize = mode == "large" ? 256 : mode == "default" ? 104 : 64
        settings.movement = mode == "still" ? .stationary : mode == "vertical" ? .up : .left
        settings.colorMode = mode == "tint" ? .tinted : mode == "mono" ? .monochrome : .original
        settings.spacing = mode == "zero" ? 0 : 0.08
        let views = mode == "single" ? 1 : mode == "double" ? 2 : 3
        let renderers = (0..<views).map { _ in MosaicRenderer() }
        func configure() {
            for (index, renderer) in renderers.enumerated() {
                renderer.configure(settings: settings, apps: selected, size: CGSize(width: 1920, height: 1080),
                                   scale: 1, backingScale: index == 1 ? 2 : 1, emptyMessage: nil)
                renderer.resume()
            }
        }
        let start = cpu(), wall = Date()
        configure()
        let initialCounts = renderers.map { tree($0.root) }
        let deadline = Date().addingTimeInterval(120)
        while renderers.contains(where: { $0.readyCount != $0.cellCount }) && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(renderers.allSatisfy { $0.readyCount == $0.cellCount }, "artwork timeout")
        let startup = cpu() - start, startupWall = Date().timeIntervalSince(wall)
        let counts = renderers.map { tree($0.root) }
        let rebuilds = renderers.reduce(0) { $0 + $1.rebuildCount }
        let requests = MosaicArtworkCache.shared.requests
        let duplicateStart = cpu()
        for _ in 0..<5 { configure() }
        let duplicateCPU = cpu() - duplicateStart
        let duplicateRebuilds = renderers.reduce(0) { $0 + $1.rebuildCount } - rebuilds
        let duplicateRequests = MosaicArtworkCache.shared.requests - requests
        let recoveryStart = cpu()
        let recoveryDeadline = Date().addingTimeInterval(120)
        while renderers.contains(where: { $0.readyCount != $0.cellCount }) && Date() < recoveryDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(renderers.allSatisfy { $0.readyCount == $0.cellCount })
        let recoveryCPU = cpu() - recoveryStart
        let warmStart = cpu(), beforeDecodes = MosaicArtworkCache.shared.decodes
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        let warm = cpu() - warmStart
        var r = rusage(); getrusage(RUSAGE_SELF, &r)
        let result: [String: Any] = ["mode": mode, "apps": selected.count, "views": views,
            "cells": renderers.reduce(0) { $0 + $1.cellCount }, "layers": counts.reduce(0) { $0 + $1.0 },
            "installedAnimations": initialCounts.reduce(0) { $0 + $1.1 }, "startupCPU": startup, "startupWall": startupWall,
            "peakRSSBytes": r.ru_maxrss, "duplicateCPU": duplicateCPU, "duplicateRebuilds": duplicateRebuilds,
            "duplicateRequests": duplicateRequests, "recoveryCPU": recoveryCPU, "warmCPU3s": warm,
            "warmDecodes": MosaicArtworkCache.shared.decodes - beforeDecodes]
        print(String(data: try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
        for renderer in renderers { renderer.stop(); precondition(renderer.cellCount == 0) }
    }
}
