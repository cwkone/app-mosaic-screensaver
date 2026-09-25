import AppKit
import CoreLocation

final class MosaicScheduleController: NSObject, CLLocationManagerDelegate {
    let window: NSWindow
    private var draft: MosaicTintSchedule
    private let onSave: (MosaicTintSchedule) -> Void
    private let mode = NSPopUpButton()
    private let dayTime = NSDatePicker()
    private let nightTime = NSDatePicker()
    private let transition = NSSlider(value: 60, minValue: 10, maxValue: 180, target: nil, action: nil)
    private let transitionValue = NSTextField(labelWithString: "")
    private let dayStrength = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let nightStrength = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let locationName = NSTextField()
    private let latitude = NSTextField()
    private let longitude = NSTextField()
    private let status = NSTextField(labelWithString: "")
    private var manager: CLLocationManager?

    init(schedule: MosaicTintSchedule, onSave: @escaping (MosaicTintSchedule) -> Void) {
        draft = schedule; self.onSave = onSave
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 430),
                          styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        window.title = "Tint Schedule & Location"; window.isReleasedWhenClosed = false
        build(); refresh()
    }

    private func label(_ text: String, y: CGFloat) {
        let view = NSTextField(labelWithString: text); view.frame = NSRect(x: 24, y: y, width: 150, height: 22)
        window.contentView?.addSubview(view)
    }
    private func build() {
        let title = NSTextField(labelWithString: "Automatic Tint")
        title.font = .systemFont(ofSize: 22, weight: .semibold); title.frame = NSRect(x: 24, y: 378, width: 490, height: 30)
        window.contentView?.addSubview(title)
        label("Mode", y: 337)
        mode.frame = NSRect(x: 178, y: 331, width: 230, height: 28)
        mode.addItems(withTitles: MosaicTintSchedule.Mode.allCases.map(\.title)); mode.target = self; mode.action = #selector(changed)
        window.contentView?.addSubview(mode)
        label("Day begins", y: 296); configure(dayTime, y: 290)
        label("Night begins", y: 255); configure(nightTime, y: 249)
        label("Color transition", y: 214)
        transition.frame = NSRect(x: 178, y: 207, width: 230, height: 24); transition.target = self; transition.action = #selector(changed)
        transitionValue.frame = NSRect(x: 418, y: 211, width: 95, height: 20); transitionValue.textColor = .secondaryLabelColor
        window.contentView?.addSubview(transition); window.contentView?.addSubview(transitionValue)
        label("Tint strength", y: 172)
        dayStrength.frame = NSRect(x: 178, y: 169, width: 105, height: 20); dayStrength.target = self; dayStrength.action = #selector(changed)
        nightStrength.frame = NSRect(x: 303, y: 169, width: 105, height: 20); nightStrength.target = self; nightStrength.action = #selector(changed)
        let strengths = NSTextField(labelWithString: "Day                                Night")
        strengths.font = .systemFont(ofSize: 10); strengths.textColor = .secondaryLabelColor
        strengths.frame = NSRect(x: 178, y: 150, width: 250, height: 17); window.contentView?.addSubview(strengths)
        label("Location", y: 116)
        locationName.frame = NSRect(x: 178, y: 111, width: 230, height: 24); locationName.placeholderString = "City, state, or country"
        let find = NSButton(title: "Find", target: self, action: #selector(findLocation)); find.frame = NSRect(x: 412, y: 109, width: 82, height: 28)
        window.contentView?.addSubview(locationName); window.contentView?.addSubview(find)
        label("Coordinates", y: 78)
        latitude.frame = NSRect(x: 178, y: 73, width: 108, height: 24); latitude.placeholderString = "Latitude"
        longitude.frame = NSRect(x: 300, y: 73, width: 108, height: 24); longitude.placeholderString = "Longitude"
        let current = NSButton(title: "Use Current", target: self, action: #selector(useCurrentLocation)); current.frame = NSRect(x: 412, y: 71, width: 102, height: 28)
        current.toolTip = "Current Location is available from the preview app. Manual location works from either options window."
        window.contentView?.addSubview(latitude); window.contentView?.addSubview(longitude); window.contentView?.addSubview(current)
        status.frame = NSRect(x: 24, y: 43, width: 360, height: 20); status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        window.contentView?.addSubview(status)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel)); cancel.frame = NSRect(x: 350, y: 10, width: 80, height: 30); cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Done", target: self, action: #selector(save)); save.frame = NSRect(x: 434, y: 10, width: 80, height: 30); save.keyEquivalent = "\r"
        window.contentView?.addSubview(cancel); window.contentView?.addSubview(save)
    }
    private func configure(_ picker: NSDatePicker, y: CGFloat) {
        picker.datePickerElements = [.hourMinute]; picker.datePickerStyle = .textFieldAndStepper
        picker.frame = NSRect(x: 178, y: y, width: 230, height: 27); picker.target = self; picker.action = #selector(changed)
        window.contentView?.addSubview(picker)
    }
    private func refresh() {
        mode.selectItem(at: MosaicTintSchedule.Mode.allCases.firstIndex(of: draft.mode) ?? 0)
        dayTime.dateValue = Self.date(minutes: draft.dayStartMinutes)
        nightTime.dateValue = Self.date(minutes: draft.nightStartMinutes)
        transition.doubleValue = Double(draft.transitionMinutes)
        dayStrength.doubleValue = draft.dayStrength; nightStrength.doubleValue = draft.nightStrength
        locationName.stringValue = draft.locationName
        latitude.stringValue = draft.latitude.map { String(format: "%.6f", $0) } ?? ""
        longitude.stringValue = draft.longitude.map { String(format: "%.6f", $0) } ?? ""
        changed()
    }
    @objc private func changed() {
        let solar = MosaicTintSchedule.Mode.allCases[mode.indexOfSelectedItem] == .sunriseSunset
        dayTime.isEnabled = !solar; nightTime.isEnabled = !solar
        locationName.isEnabled = solar; latitude.isEnabled = solar; longitude.isEnabled = solar
        transitionValue.stringValue = "\(Int(transition.doubleValue.rounded())) min"
    }
    @objc private func save() {
        draft.mode = MosaicTintSchedule.Mode.allCases[mode.indexOfSelectedItem]
        draft.dayStartMinutes = Self.minutes(dayTime.dateValue)
        draft.nightStartMinutes = Self.minutes(nightTime.dateValue)
        draft.transitionMinutes = Int(transition.doubleValue.rounded())
        draft.dayStrength = dayStrength.doubleValue; draft.nightStrength = nightStrength.doubleValue
        draft.locationName = locationName.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lat = Double(latitude.stringValue), lon = Double(longitude.stringValue)
        if draft.mode == .sunriseSunset {
            guard let lat, let lon, (-90...90).contains(lat), (-180...180).contains(lon) else {
                status.stringValue = "Enter a latitude from −90 to 90 and longitude from −180 to 180."
                status.textColor = .systemRed; return
            }
            draft.latitude = lat; draft.longitude = lon
        } else {
            draft.latitude = lat; draft.longitude = lon
        }
        onSave(draft); dismiss()
    }
    @objc private func cancel() { dismiss() }
    private func dismiss() { if let parent = window.sheetParent { parent.endSheet(window) } else { window.orderOut(nil) } }

    @objc private func findLocation() {
        let query = locationName.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { status.stringValue = "Enter a city or place name first."; return }
        status.textColor = .secondaryLabelColor; status.stringValue = "Finding location…"
        CLGeocoder().geocodeAddressString(query) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let location = placemarks?.first?.location {
                    self.set(location: location)
                    self.status.stringValue = "Location found."
                } else { self.status.stringValue = error?.localizedDescription ?? "Location not found." }
            }
        }
    }
    @objc private func useCurrentLocation() {
        guard Bundle.main.bundleIdentifier == "one.cwk.AppMosaic.Preview" else {
            status.stringValue = "Open the App Mosaic Preview app to grant Current Location access."
            return
        }
        status.textColor = .secondaryLabelColor; status.stringValue = "Requesting current location…"
        let manager = CLLocationManager(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        self.manager = manager
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways: manager.requestLocation()
        default: status.stringValue = "Location access is unavailable. Enter a place or coordinates instead."
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
        else if manager.authorizationStatus != .notDetermined { status.stringValue = "Location access was not granted. Manual location still works." }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        set(location: location); status.stringValue = "Current location saved at city-level precision."
        self.manager = nil
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status.stringValue = error.localizedDescription; self.manager = nil
    }
    private func set(location: CLLocation) {
        // Three decimal places is ample for sunrise/sunset and avoids storing a precise address.
        latitude.stringValue = String(format: "%.3f", location.coordinate.latitude)
        longitude.stringValue = String(format: "%.3f", location.coordinate.longitude)
    }
    private static func date(minutes: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? Date()
    }
    private static func minutes(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
