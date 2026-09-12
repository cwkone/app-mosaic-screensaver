import AppKit

final class MosaicOptionsController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let window: NSWindow
    private(set) var draft: MosaicSettings
    private var apps: [InstalledApp]
    private let onSave: (MosaicSettings) -> Void
    private var sliders: [String: NSSlider] = [:]
    private var values: [String: NSTextField] = [:]
    private let movement = NSPopUpButton()
    private let screenEdges = NSPopUpButton()
    private let colorMode = NSPopUpButton()
    private let tintColor = NSColorWell()
    private var formContainer: NSView?
    private let tabs = NSTabView()
    private let appSummary = NSTextField(labelWithString: "")
    private var chooser: NSWindow?
    private let table = NSTableView()
    private let search = NSSearchField()
    private let selectionSummary = NSTextField(labelWithString: "")
    private let cache = IconCache()
    private var filtered: [InstalledApp] {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    init(settings: MosaicSettings, apps: [InstalledApp], onSave: @escaping (MosaicSettings) -> Void) {
        self.draft = settings; self.apps = apps; self.onSave = onSave
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 610),
                          styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        window.title = "App Mosaic Options"
        window.isReleasedWhenClosed = false
        build()
        refresh()
    }
    private func label(_ text: String, frame: NSRect, size: CGFloat = 13, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame; label.font = .systemFont(ofSize: size); label.textColor = color
        (formContainer ?? window.contentView)?.addSubview(label)
        return label
    }
    private func pane(_ title: String) {
        let item = NSTabViewItem(identifier: title); item.label = title
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 345))
        item.view = view; tabs.addTabViewItem(item); formContainer = view
    }
    private func popup(_ control: NSPopUpButton, title: String, y: CGFloat, choices: [String]) {
        _ = label(title, frame: NSRect(x: 20, y: y + 4, width: 165, height: 22))
        control.frame = NSRect(x: 194, y: y, width: 236, height: 28)
        control.addItems(withTitles: choices)
        control.target = self; control.action = #selector(changed)
        control.setAccessibilityLabel(title)
        formContainer?.addSubview(control)
    }
    private func build() {
        _ = label("App Mosaic", frame: NSRect(x: 28, y: 554, width: 580, height: 32), size: 25)
        _ = label("Your apps, quietly in motion.", frame: NSRect(x: 28, y: 526, width: 580, height: 22), color: .secondaryLabelColor)
        tabs.frame = NSRect(x: 24, y: 119, width: 592, height: 390)
        window.contentView?.addSubview(tabs)
        pane("Layout")
        addSlider("iconSize", title: "Icon size", y: 278, range: 64...256, low: "Small", high: "Large")
        addSlider("spacing", title: "Grid spacing", y: 208, range: 0...0.6, low: "Tight", high: "Spacious")
        popup(screenEdges, title: "Screen edges", y: 145, choices: MosaicSettings.ScreenEdges.allCases.map(\.title))
        addSlider("edgeMargin", title: "Screen margin", y: 85, range: 0...0.15, low: "None", high: "Wide")
        _ = label("Fill the screen lets icons continue beyond the edges.", frame: NSRect(x: 20, y: 24, width: 520, height: 22), size: 11, color: .secondaryLabelColor)
        pane("Animation")
        addSlider("frequency", title: "Change frequency", y: 278, range: 0...1, low: "Occasionally", high: "Often")
        addSlider("fadeDuration", title: "Fade duration", y: 208, range: 0.2...10, low: "Quick", high: "Lingering")
        popup(movement, title: "Grid movement", y: 145, choices: MosaicSettings.Movement.allCases.map(\.title))
        addSlider("scrollSpeed", title: "Scroll speed", y: 85, range: 0...1, low: "Barely moving", high: "Flowing")
        _ = label("Fade and scroll speeds are independent. Fades stay staggered.", frame: NSRect(x: 20, y: 24, width: 530, height: 22), size: 11, color: .secondaryLabelColor)
        pane("Appearance")
        addSlider("edgeFade", title: "Fade at screen edges", y: 278, range: 0...0.3, low: "Off", high: "Broad")
        popup(colorMode, title: "Icon colors", y: 213, choices: MosaicSettings.ColorMode.allCases.map(\.title))
        _ = label("Tint color", frame: NSRect(x: 20, y: 156, width: 165, height: 22))
        tintColor.frame = NSRect(x: 196, y: 148, width: 64, height: 34)
        tintColor.colorWellStyle = .expanded; tintColor.supportsAlpha = false
        tintColor.target = self; tintColor.action = #selector(changed)
        tintColor.setAccessibilityLabel("Tint color")
        formContainer?.addSubview(tintColor)
        addSlider("tintStrength", title: "Tint strength", y: 85, range: 0...1, low: "Original colors", high: "Full tint")
        _ = label("Tinting preserves the details and shape of each app icon.", frame: NSRect(x: 20, y: 24, width: 530, height: 22), size: 11, color: .secondaryLabelColor)
        formContainer = nil
        let choose = NSButton(title: "Choose Apps…", target: self, action: #selector(showChooser))
        choose.bezelStyle = .rounded; choose.frame = NSRect(x: 22, y: 71, width: 145, height: 32)
        window.contentView?.addSubview(choose)
        appSummary.frame = NSRect(x: 179, y: 77, width: 425, height: 20)
        appSummary.font = .systemFont(ofSize: 12); appSummary.textColor = .secondaryLabelColor
        window.contentView?.addSubview(appSummary)
        let line = NSBox(frame: NSRect(x: 28, y: 58, width: 584, height: 1)); line.boxType = .separator
        window.contentView?.addSubview(line)
        let restore = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        restore.bezelStyle = .rounded; restore.frame = NSRect(x: 22, y: 13, width: 150, height: 32)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded; cancel.frame = NSRect(x: 434, y: 13, width: 85, height: 32); cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Done", target: self, action: #selector(save))
        save.bezelStyle = .rounded; save.frame = NSRect(x: 523, y: 13, width: 89, height: 32); save.keyEquivalent = "\r"
        for button in [restore, cancel, save] { window.contentView?.addSubview(button) }
    }
    private func addSlider(_ key: String, title: String, y: CGFloat, range: ClosedRange<Double>, low: String, high: String) {
        _ = label(title, frame: NSRect(x: 20, y: y + 4, width: 165, height: 22))
        let slider = NSSlider(value: 0, minValue: range.lowerBound, maxValue: range.upperBound, target: self, action: #selector(changed))
        slider.frame = NSRect(x: 194, y: y, width: 236, height: 28)
        slider.identifier = NSUserInterfaceItemIdentifier(key)
        slider.isContinuous = true; slider.setAccessibilityLabel(title)
        sliders[key] = slider; formContainer?.addSubview(slider)
        values[key] = label("", frame: NSRect(x: 439, y: y + 3, width: 102, height: 22), size: 12, color: .secondaryLabelColor)
        _ = label(low, frame: NSRect(x: 196, y: y - 19, width: 145, height: 17), size: 11, color: .secondaryLabelColor)
        let right = label(high, frame: NSRect(x: 322, y: y - 19, width: 106, height: 17), size: 11, color: .secondaryLabelColor)
        right.alignment = .right
    }
    @objc private func changed() {
        draft.iconSize = sliders["iconSize"]!.doubleValue
        draft.spacing = sliders["spacing"]!.doubleValue
        draft.edgeMargin = sliders["edgeMargin"]!.doubleValue
        draft.edgeFade = sliders["edgeFade"]!.doubleValue
        draft.frequency = sliders["frequency"]!.doubleValue
        draft.fadeDuration = sliders["fadeDuration"]!.doubleValue
        draft.scrollSpeed = sliders["scrollSpeed"]!.doubleValue
        draft.tintStrength = sliders["tintStrength"]!.doubleValue
        draft.movement = MosaicSettings.Movement(rawValue: movement.indexOfSelectedItem) ?? .stationary
        draft.screenEdges = MosaicSettings.ScreenEdges(rawValue: screenEdges.indexOfSelectedItem) ?? .fill
        draft.colorMode = MosaicSettings.ColorMode(rawValue: colorMode.indexOfSelectedItem) ?? .original
        if let color = tintColor.color.usingColorSpace(.sRGB) {
            if abs(draft.tintRed - Double(color.redComponent)) > 0.000001 { draft.tintRed = Double(color.redComponent) }
            if abs(draft.tintGreen - Double(color.greenComponent)) > 0.000001 { draft.tintGreen = Double(color.greenComponent) }
            if abs(draft.tintBlue - Double(color.blueComponent)) > 0.000001 { draft.tintBlue = Double(color.blueComponent) }
        }
        updateValues()
    }
    private func refresh() {
        let fields: [String: Double] = ["iconSize": draft.iconSize, "spacing": draft.spacing, "edgeMargin": draft.edgeMargin,
            "edgeFade": draft.edgeFade, "frequency": draft.frequency, "fadeDuration": draft.fadeDuration,
            "scrollSpeed": draft.scrollSpeed, "tintStrength": draft.tintStrength]
        for (key, value) in fields { sliders[key]?.doubleValue = value }
        movement.selectItem(at: draft.movement.rawValue)
        screenEdges.selectItem(at: draft.screenEdges.rawValue)
        colorMode.selectItem(at: draft.colorMode.rawValue)
        tintColor.color = NSColor(srgbRed: draft.tintRed, green: draft.tintGreen, blue: draft.tintBlue, alpha: 1)
        updateValues()
    }
    private func updateValues() {
        values["iconSize"]?.stringValue = "\(Int(draft.iconSize)) pt"
        values["spacing"]?.stringValue = "\(Int((draft.spacing * 100).rounded()))%"
        values["edgeMargin"]?.stringValue = draft.edgeMargin < 0.001 ? "None" : String(format: "%.0f%%", draft.edgeMargin * 100)
        values["edgeFade"]?.stringValue = draft.edgeFade < 0.001 ? "Off" : String(format: "%.0f%%", draft.edgeFade * 100)
        values["frequency"]?.stringValue = String(format: "Every %.2g s", draft.changeInterval)
        values["fadeDuration"]?.stringValue = String(format: "%.1f s each", draft.fadeDuration)
        values["scrollSpeed"]?.stringValue = String(format: "%.0f s / cell", draft.secondsPerCell)
        values["tintStrength"]?.stringValue = String(format: "%.0f%%", draft.tintStrength * 100)
        sliders["scrollSpeed"]?.isEnabled = draft.movement != .stationary
        values["scrollSpeed"]?.textColor = draft.movement == .stationary ? .disabledControlTextColor : .secondaryLabelColor
        let tinting = draft.colorMode == .tinted
        tintColor.isEnabled = tinting; sliders["tintStrength"]?.isEnabled = tinting
        values["tintStrength"]?.textColor = tinting ? .secondaryLabelColor : .disabledControlTextColor
        let selected = apps.filter { !draft.excludedApps.contains($0.id) }.count
        appSummary.stringValue = apps.isEmpty ? "No apps found in standard Applications folders." : "\(selected) of \(apps.count) apps included"
        selectionSummary.stringValue = "\(selected) included · New apps are included automatically"
    }
    @objc func restoreDefaults() { draft = .defaults; refresh(); table.reloadData() }
    @objc func save() { changed(); onSave(draft); dismiss(.OK) }
    @objc func cancel() { dismiss(.cancel) }
    private func dismiss(_ result: NSApplication.ModalResponse) {
        if let parent = window.sheetParent { parent.endSheet(window, returnCode: result) }
        else { window.orderOut(nil) }
    }
    func updateApps(_ apps: [InstalledApp]) { self.apps = apps; table.reloadData(); updateValues() }

    @objc func showChooser() {
        if chooser == nil { buildChooser() }
        search.stringValue = ""; table.reloadData(); updateValues()
        if let chooser { window.beginSheet(chooser) }
    }
    private func buildChooser() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                             styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Choose Apps"; panel.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "Choose Apps")
        title.font = .systemFont(ofSize: 22, weight: .semibold); title.frame = NSRect(x: 24, y: 500, width: 512, height: 30)
        let subtitle = NSTextField(labelWithString: "Uncheck any apps you’d rather leave out.")
        subtitle.textColor = .secondaryLabelColor; subtitle.frame = NSRect(x: 24, y: 475, width: 512, height: 22)
        search.frame = NSRect(x: 24, y: 431, width: 512, height: 28)
        search.placeholderString = "Search installed apps"; search.delegate = self
        search.setAccessibilityLabel("Search installed apps")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.width = 486; table.addTableColumn(column); table.headerView = nil
        table.rowHeight = 40; table.delegate = self; table.dataSource = self
        table.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView(frame: NSRect(x: 24, y: 110, width: 512, height: 307))
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        selectionSummary.font = .systemFont(ofSize: 11); selectionSummary.textColor = .secondaryLabelColor
        selectionSummary.frame = NSRect(x: 24, y: 79, width: 512, height: 20)
        let all = NSButton(title: "Include All", target: self, action: #selector(includeAll))
        all.bezelStyle = .rounded; all.frame = NSRect(x: 18, y: 20, width: 112, height: 32)
        let none = NSButton(title: "Exclude All", target: self, action: #selector(excludeAll))
        none.bezelStyle = .rounded; none.frame = NSRect(x: 132, y: 20, width: 112, height: 32)
        let done = NSButton(title: "Done", target: self, action: #selector(closeChooser))
        done.bezelStyle = .rounded; done.frame = NSRect(x: 448, y: 20, width: 88, height: 32); done.keyEquivalent = "\r"
        for view in [title, subtitle, search, scroll, selectionSummary, all, none, done] { panel.contentView?.addSubview(view) }
        chooser = panel
    }
    @objc func includeAll() { draft.excludedApps = []; table.reloadData(); updateValues() }
    @objc func excludeAll() { draft.excludedApps.formUnion(apps.map(\.id)); table.reloadData(); updateValues() }
    @objc func closeChooser() { if let chooser { window.endSheet(chooser) } }
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = filtered[row]
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 486, height: 40))
        let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleApp(_:)))
        check.frame = NSRect(x: 7, y: 9, width: 22, height: 22); check.tag = row
        check.state = draft.excludedApps.contains(app.id) ? .off : .on
        check.setAccessibilityLabel("Include \(app.name)")
        let icon = NSImageView(frame: NSRect(x: 37, y: 5, width: 30, height: 30)); icon.image = cache.image(for: app)
        let name = NSTextField(labelWithString: app.name)
        name.frame = NSRect(x: 79, y: 10, width: 395, height: 22); name.lineBreakMode = .byTruncatingTail
        name.toolTip = app.url.path
        for child in [check, icon, name] { view.addSubview(child) }
        return view
    }
    @objc private func toggleApp(_ sender: NSButton) {
        guard filtered.indices.contains(sender.tag) else { return }
        let id = filtered[sender.tag].id
        if sender.state == .on { draft.excludedApps.remove(id) } else { draft.excludedApps.insert(id) }
        updateValues()
    }
    func controlTextDidChange(_ obj: Notification) { table.reloadData() }
}
