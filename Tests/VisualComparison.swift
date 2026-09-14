import AppKit
import QuartzCore
@main struct Comparison {
    static func main() {
        _ = NSApplication.shared
        let app = InstalledApp(id: "finder", name: "Finder", url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        var passed = 0
        for movement in MosaicSettings.Movement.allCases {
            for variant in 0..<7 {
                var settings = MosaicSettings(); settings.movement = movement
                settings.iconSize = variant == 0 ? 64 : variant == 1 ? 256 : 104
                settings.colorMode = variant == 2 ? .tinted : variant == 3 ? .monochrome : .original
                settings.spacing = variant == 4 ? 0 : 0.08
                settings.edgeMargin = variant == 5 ? 0.1 : 0
                settings.edgeFade = variant == 6 ? 0.18 : 0
                settings.screenEdges = variant == 5 ? .wholeIcons : .fill
                let before = ReferenceRenderer(), after = MosaicRenderer()
                let size = CGSize(width: 800, height: 480)
                before.configure(settings: settings, apps: [app], size: size, scale: 1, backingScale: 2, emptyMessage: nil)
                after.configure(settings: settings, apps: [app], size: size, scale: 1, backingScale: 2, emptyMessage: nil)
                let deadline = Date().addingTimeInterval(30)
                while (before.readyCount != before.cellCount || after.readyCount != after.cellCount) && Date() < deadline {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                }
                precondition(before.readyCount == before.cellCount && after.readyCount == after.cellCount)
                let old = before.snapshot()!, new = after.snapshot()!
                let oldBytes = Data(bytes: old.bitmapData!, count: old.bytesPerRow * old.pixelsHigh)
                let newBytes = Data(bytes: new.bitmapData!, count: new.bytesPerRow * new.pixelsHigh)
                precondition(oldBytes == newBytes, "pixels differ: \(movement) variant \(variant)")
                if movement == .stationary || variant == 6 {
                    try! new.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "QA/performance/compare-\(movement)-\(variant).png"))
                }
                passed += 1
                before.stop(); after.stop()
            }
        }
        print("PASS: \(passed) pixel-identical offscreen layer snapshots against release da62bb6, all directions, small/large icons, original/tinted/monochrome, zero spacing, whole icons/margin, edge fades, 2x artwork")
    }
}
