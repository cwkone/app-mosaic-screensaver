import AppKit

@main struct CatalogTests {
    static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppMosaicTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func fixture(_ path: String, id: String, extras: [String: Any] = [:]) throws {
            let contents = root.appendingPathComponent(path + "/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": id, "CFBundlePackageType": "APPL"]
            info.merge(extras) { _, new in new }
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        try fixture("Alpha.app", id: "alpha")
        try fixture("Folder/AlphaCopy.app", id: "alpha")
        try fixture("Folder/Menu.app", id: "menu", extras: ["LSUIElement": true])
        try fixture("Alpha.app/Contents/Helper.app", id: "helper")
        try fixture(".Hidden/Hidden.app", id: "hidden")
        try fixture("Daemon.app", id: "daemon", extras: ["LSBackgroundOnly": true])
        try fixture("UE_5/Engine/Binaries/Mac/UnrealEditor.app", id: "unreal")
        try fixture("UE_5/Engine/Source/Tests/Fixture.app", id: "test-fixture")
        try fixture("Tool/node_modules/Dependency.app", id: "dependency")
        let discovered = AppCatalog.discover(in: [root])
        precondition(Set(discovered.map(\.id)) == ["alpha", "menu", "unreal"])
        precondition(discovered.count == 3)
        precondition(discovered.first(where: { $0.id == "menu" })?.name == "Menu")
        print("PASS: app subfolders, deduplication, menu bar apps, nested helper exclusion, hidden folders, background agents, SDK source/dependency exclusion, nested Unreal Editor")
    }
}
