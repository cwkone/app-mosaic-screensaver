import AppKit

final class MosaicOptionsController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let window: NSWindow
    private(set) var draftLibrary: MosaicPresetLibrary
    private(set) var draft: MosaicSettings
    private var apps: [InstalledApp]
    private let onSave: (MosaicPresetLibrary) -> Void
    private var sliders: [String: NSSlider] = [:]
    private var values: [String: NSTextField] = [:]
    private let movement = NSPopUpButton()
    private let screenEdges = NSPopUpButton()
    private let colorMode = NSPopUpButton()
    private let tintColor = NSColorWell()
    private let presetPopup = NSPopUpButton()
    private let groupPopup = NSPopUpButton()
    private let tintSchedulePopup = NSPopUpButton()
    private let dayTintColor = NSColorWell()
    private let nightTintColor = NSColorWell()
    private let scheduleSummary = NSTextField(labelWithString: "")
    private var scheduleController: MosaicScheduleController?
    private var formContainer: NSView?
    private let tabs = NSTabView()
    private let appSummary = NSTextField(labelWithString: "")
    private var chooser: NSWindow?
    private let table = NSTableView()
    private let search = NSSearchField()
    private let selectionSummary = NSTextField(labelWithString: "")
    private let cache = IconCache()
    private var filtered: [InstalledApp] = []
    private var summaryExclusions: Set<String>?
    private func refilter() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    init(library: MosaicPresetLibrary, apps: [InstalledApp], onSave: @escaping (MosaicPresetLibrary) -> Void) {
        var library = library
        library.normalize()
        self.draftLibrary = library
        self.apps = apps
        self.onSave = onSave
        let preset = library.presets.first(where: { $0.id == library.selectedPresetID }) ?? library.presets[0]
        var settings = preset.settings
        if let group = library.groups.first(where: { $0.id == preset.appGroupID }) {
            settings.excludedApps = group.excludedApps(from: Set(apps.map(\.id)))
        }
        self.draft = settings
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 610),
                          styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        window.title = "App Mosaic Options"
        window.isReleasedWhenClosed = false
        build()
        refilter()
        refresh()
    }

    convenience init(settings: MosaicSettings, apps: [InstalledApp], onSave: @escaping (MosaicSettings) -> Void) {
        self.init(library: MosaicPresetLibrary.initial(settings: settings), apps: apps) { library in
            let preset = library.presets.first(where: { $0.id == library.selectedPresetID }) ?? library.presets[0]
            var result = preset.settings
            if let group = library.groups.first(where: { $0.id == preset.appGroupID }) {
                result.excludedApps = group.excludedApps(from: Set(apps.map(\.id)))
            }
            onSave(result)
        }
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
        pane("Presets")
        _ = label("Preset", frame: NSRect(x: 20, y: 286, width: 100, height: 22))
        presetPopup.frame = NSRect(x: 122, y: 280, width: 210, height: 28)
        presetPopup.target = self; presetPopup.action = #selector(selectPreset)
        formContainer?.addSubview(presetPopup)
        addCompactButton("New", x: 338, y: 280, width: 58, action: #selector(newPreset))
        addCompactButton("Rename", x: 398, y: 280, width: 72, action: #selector(renamePreset))
        addCompactButton("Delete", x: 472, y: 280, width: 68, action: #selector(deletePreset))
        _ = label("App group", frame: NSRect(x: 20, y: 229, width: 100, height: 22))
        groupPopup.frame = NSRect(x: 122, y: 223, width: 210, height: 28)
        groupPopup.target = self; groupPopup.action = #selector(selectGroup)
        formContainer?.addSubview(groupPopup)
        addCompactButton("New", x: 338, y: 223, width: 58, action: #selector(newGroup))
        addCompactButton("Rename", x: 398, y: 223, width: 72, action: #selector(renameGroup))
        addCompactButton("Delete", x: 472, y: 223, width: 68, action: #selector(deleteGroup))
        _ = label("Automatic tint", frame: NSRect(x: 20, y: 170, width: 100, height: 22))
        tintSchedulePopup.frame = NSRect(x: 122, y: 164, width: 210, height: 28)
        tintSchedulePopup.addItems(withTitles: MosaicTintSchedule.Mode.allCases.map(\.title))
        tintSchedulePopup.target = self; tintSchedulePopup.action = #selector(scheduleChanged)
        formContainer?.addSubview(tintSchedulePopup)
        _ = label("Day tint", frame: NSRect(x: 20, y: 112, width: 100, height: 22))
        dayTintColor.frame = NSRect(x: 122, y: 104, width: 62, height: 34)
        dayTintColor.colorWellStyle = .expanded; dayTintColor.supportsAlpha = false
        dayTintColor.target = self; dayTintColor.action = #selector(scheduleChanged)
        dayTintColor.setAccessibilityLabel("Day tint")
        formContainer?.addSubview(dayTintColor)
        _ = label("Night tint", frame: NSRect(x: 214, y: 112, width: 100, height: 22))
        nightTintColor.frame = NSRect(x: 306, y: 104, width: 62, height: 34)
        nightTintColor.colorWellStyle = .expanded; nightTintColor.supportsAlpha = false
        nightTintColor.target = self; nightTintColor.action = #selector(scheduleChanged)
        nightTintColor.setAccessibilityLabel("Night tint")
        formContainer?.addSubview(nightTintColor)
        addCompactButton("Schedule & Location…", x: 20, y: 45, width: 176, action: #selector(showSchedule))
        scheduleSummary.frame = NSRect(x: 207, y: 51, width: 333, height: 36)
        scheduleSummary.font = .systemFont(ofSize: 11); scheduleSummary.textColor = .secondaryLabelColor
        scheduleSummary.maximumNumberOfLines = 2; scheduleSummary.lineBreakMode = .byWordWrapping
        formContainer?.addSubview(scheduleSummary)
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
    private func addCompactButton(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, action: Selector) {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded; button.controlSize = .small
        button.frame = NSRect(x: x, y: y, width: width, height: 28)
        formContainer?.addSubview(button)
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
        commitSettingsToPreset()
        updateValues()
    }
    private func refresh() {
        reloadPresetMenus()
        let fields: [String: Double] = ["iconSize": draft.iconSize, "spacing": draft.spacing, "edgeMargin": draft.edgeMargin,
            "edgeFade": draft.edgeFade, "frequency": draft.frequency, "fadeDuration": draft.fadeDuration,
            "scrollSpeed": draft.scrollSpeed, "tintStrength": draft.tintStrength]
        for (key, value) in fields { sliders[key]?.doubleValue = value }
        movement.selectItem(at: draft.movement.rawValue)
        screenEdges.selectItem(at: draft.screenEdges.rawValue)
        colorMode.selectItem(at: draft.colorMode.rawValue)
        tintColor.color = NSColor(srgbRed: draft.tintRed, green: draft.tintGreen, blue: draft.tintBlue, alpha: 1)
        if let preset = currentPreset {
            tintSchedulePopup.selectItem(at: MosaicTintSchedule.Mode.allCases.firstIndex(of: preset.tintSchedule.mode) ?? 0)
            dayTintColor.color = NSColor(srgbRed: preset.tintSchedule.dayColor.red,
                                         green: preset.tintSchedule.dayColor.green,
                                         blue: preset.tintSchedule.dayColor.blue, alpha: 1)
            nightTintColor.color = NSColor(srgbRed: preset.tintSchedule.nightColor.red,
                                           green: preset.tintSchedule.nightColor.green,
                                           blue: preset.tintSchedule.nightColor.blue, alpha: 1)
            updateScheduleSummary(preset.tintSchedule)
        }
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
        guard summaryExclusions != draft.excludedApps else { return }
        summaryExclusions = draft.excludedApps
        let selected = apps.lazy.filter { !self.draft.excludedApps.contains($0.id) }.count
        appSummary.stringValue = apps.isEmpty ? "No apps found in standard Applications folders." : "\(selected) of \(apps.count) apps included"
        let newApps = currentGroupIndex.flatMap { draftLibrary.groups[$0].rule } == .only
            ? "New apps remain excluded"
            : "New apps are included automatically"
        selectionSummary.stringValue = "\(selected) included · \(newApps)"
    }
    @objc func restoreDefaults() {
        draft = .defaults
        if let index = currentPresetIndex { draftLibrary.presets[index].tintSchedule = MosaicTintSchedule() }
        if let index = currentGroupIndex {
            draftLibrary.groups[index].rule = .allExcept
            draftLibrary.groups[index].appIDs = []
        }
        commitSettingsToPreset(); summaryExclusions = nil; refresh(); table.reloadData()
    }
    @objc func save() {
        changed(); commitSelectionToGroup()
        draftLibrary.selectedPresetID = currentPreset?.id ?? draftLibrary.selectedPresetID
        draftLibrary.normalize(fallback: draft)
        onSave(draftLibrary); dismiss(.OK)
    }
    @objc func cancel() { dismiss(.cancel) }
    private func dismiss(_ result: NSApplication.ModalResponse) {
        if let parent = window.sheetParent { parent.endSheet(window, returnCode: result) }
        else { window.orderOut(nil) }
    }
    func updateApps(_ apps: [InstalledApp]) {
        commitSelectionToGroup()
        self.apps = apps
        refilter()
        loadCurrentPreset()
    }

    private var currentPresetIndex: Int? {
        draftLibrary.presets.firstIndex { $0.id == draftLibrary.selectedPresetID }
    }
    private var currentPreset: MosaicPreset? { currentPresetIndex.map { draftLibrary.presets[$0] } }
    private var currentGroupIndex: Int? {
        guard let groupID = currentPreset?.appGroupID else { return nil }
        return draftLibrary.groups.firstIndex { $0.id == groupID }
    }

    private func commitSettingsToPreset() {
        guard let index = currentPresetIndex else { return }
        draftLibrary.presets[index].settings = draft
    }
    private func commitSelectionToGroup() {
        guard let index = currentGroupIndex else { return }
        draftLibrary.groups[index].setExcludedApps(draft.excludedApps, allAppIDs: Set(apps.map(\.id)))
        commitSettingsToPreset()
    }
    private func loadCurrentPreset() {
        guard let preset = currentPreset else { return }
        draft = preset.settings
        if let group = draftLibrary.groups.first(where: { $0.id == preset.appGroupID }) {
            draft.excludedApps = group.excludedApps(from: Set(apps.map(\.id)))
        }
        summaryExclusions = nil
        refresh(); table.reloadData()
    }
    private func reloadPresetMenus() {
        presetPopup.removeAllItems()
        for preset in draftLibrary.presets {
            presetPopup.addItem(withTitle: preset.name)
            presetPopup.lastItem?.representedObject = preset.id
        }
        if let index = draftLibrary.presets.firstIndex(where: { $0.id == draftLibrary.selectedPresetID }) {
            presetPopup.selectItem(at: index)
        }
        groupPopup.removeAllItems()
        for group in draftLibrary.groups {
            groupPopup.addItem(withTitle: group.name)
            groupPopup.lastItem?.representedObject = group.id
        }
        if let groupID = currentPreset?.appGroupID,
           let index = draftLibrary.groups.firstIndex(where: { $0.id == groupID }) { groupPopup.selectItem(at: index) }
    }

    @objc private func selectPreset() {
        guard let id = presetPopup.selectedItem?.representedObject as? String else { return }
        commitSelectionToGroup()
        draftLibrary.selectedPresetID = id
        loadCurrentPreset()
    }
    @objc private func selectGroup() {
        guard let id = groupPopup.selectedItem?.representedObject as? String,
              let presetIndex = currentPresetIndex else { return }
        commitSelectionToGroup()
        draftLibrary.presets[presetIndex].appGroupID = id
        loadCurrentPreset()
    }

    func createPreset(named name: String) {
        let name = uniqueName(name, existing: draftLibrary.presets.map(\.name))
        commitSelectionToGroup()
        let preset = MosaicPreset(id: UUID().uuidString, name: name, settings: draft,
                                  appGroupID: currentPreset?.appGroupID ?? draftLibrary.groups[0].id,
                                  tintSchedule: currentPreset?.tintSchedule ?? MosaicTintSchedule())
        draftLibrary.presets.append(preset); draftLibrary.selectedPresetID = preset.id
        loadCurrentPreset()
    }
    func createGroup(named name: String) {
        let name = uniqueName(name, existing: draftLibrary.groups.map(\.name))
        commitSelectionToGroup()
        let included = Set(apps.map(\.id)).subtracting(draft.excludedApps)
        let group = MosaicAppGroup(id: UUID().uuidString, name: name, rule: .only, appIDs: included)
        draftLibrary.groups.append(group)
        if let index = currentPresetIndex { draftLibrary.presets[index].appGroupID = group.id }
        loadCurrentPreset()
    }
    private func uniqueName(_ proposed: String, existing: [String]) -> String {
        let base = proposed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard existing.contains(base) else { return base }
        var number = 2
        while existing.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }
    private func requestName(title: String, current: String? = nil, completion: @escaping (String) -> Void) {
        let alert = NSAlert(); alert.messageText = title
        let field = NSTextField(string: current ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24); alert.accessoryView = field
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            completion(field.stringValue)
        }
    }
    @objc private func newPreset() { requestName(title: "New Preset", current: "Preset") { [weak self] in self?.createPreset(named: $0) } }
    @objc private func renamePreset() {
        guard let index = currentPresetIndex else { return }
        requestName(title: "Rename Preset", current: draftLibrary.presets[index].name) { [weak self] name in
            guard let self, let index = self.currentPresetIndex else { return }
            self.draftLibrary.presets[index].name = self.uniqueName(name, existing: self.draftLibrary.presets.enumerated().filter { $0.offset != index }.map { $0.element.name })
            self.reloadPresetMenus()
        }
    }
    @objc private func deletePreset() {
        guard draftLibrary.presets.count > 1, let index = currentPresetIndex else { return }
        draftLibrary.presets.remove(at: index)
        draftLibrary.selectedPresetID = draftLibrary.presets[max(0, index - 1)].id
        loadCurrentPreset()
    }
    @objc private func newGroup() { requestName(title: "New App Group", current: "App Group") { [weak self] in self?.createGroup(named: $0) } }
    @objc private func renameGroup() {
        guard let index = currentGroupIndex else { return }
        requestName(title: "Rename App Group", current: draftLibrary.groups[index].name) { [weak self] name in
            guard let self, let index = self.currentGroupIndex else { return }
            self.draftLibrary.groups[index].name = self.uniqueName(name, existing: self.draftLibrary.groups.enumerated().filter { $0.offset != index }.map { $0.element.name })
            self.reloadPresetMenus()
        }
    }
    @objc private func deleteGroup() {
        guard draftLibrary.groups.count > 1, let index = currentGroupIndex else { return }
        let removedID = draftLibrary.groups[index].id
        draftLibrary.groups.remove(at: index)
        let replacement = draftLibrary.groups[max(0, index - 1)].id
        for presetIndex in draftLibrary.presets.indices where draftLibrary.presets[presetIndex].appGroupID == removedID {
            draftLibrary.presets[presetIndex].appGroupID = replacement
        }
        loadCurrentPreset()
    }

    @objc private func scheduleChanged() {
        guard let index = currentPresetIndex else { return }
        var schedule = draftLibrary.presets[index].tintSchedule
        schedule.mode = MosaicTintSchedule.Mode.allCases[tintSchedulePopup.indexOfSelectedItem]
        if let color = dayTintColor.color.usingColorSpace(.sRGB) {
            schedule.dayColor = MosaicRGB(red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent))
        }
        if let color = nightTintColor.color.usingColorSpace(.sRGB) {
            schedule.nightColor = MosaicRGB(red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent))
        }
        draftLibrary.presets[index].tintSchedule = schedule
        updateScheduleSummary(schedule)
    }
    @objc private func showSchedule() {
        guard let index = currentPresetIndex else { return }
        let controller = MosaicScheduleController(schedule: draftLibrary.presets[index].tintSchedule) { [weak self] schedule in
            guard let self, let index = self.currentPresetIndex else { return }
            self.draftLibrary.presets[index].tintSchedule = schedule
            self.refresh()
        }
        scheduleController = controller
        window.beginSheet(controller.window)
    }
    private func updateScheduleSummary(_ schedule: MosaicTintSchedule) {
        switch schedule.mode {
        case .off: scheduleSummary.stringValue = "Presets can also be selected from Focus settings."
        case .timeOfDay:
            scheduleSummary.stringValue = "Day at \(Self.timeString(schedule.dayStartMinutes)); night at \(Self.timeString(schedule.nightStartMinutes))."
        case .sunriseSunset:
            if let latitude = schedule.latitude, let longitude = schedule.longitude {
                let place = schedule.locationName.isEmpty ? String(format: "%.3f, %.3f", latitude, longitude) : schedule.locationName
                scheduleSummary.stringValue = "Uses sunrise and sunset near \(place)."
            } else { scheduleSummary.stringValue = "Add a location to use sunrise and sunset." }
        }
    }
    private static func timeString(_ minutes: Int) -> String {
        let formatter = DateFormatter(); formatter.timeStyle = .short; formatter.dateStyle = .none
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? Date()
        return formatter.string(from: date)
    }

    @objc func showChooser() {
        if chooser == nil { buildChooser() }
        search.stringValue = ""; refilter(); table.reloadData(); updateValues()
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
    func controlTextDidChange(_ obj: Notification) { refilter(); table.reloadData() }
}
