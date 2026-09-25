import Foundation

struct MosaicRGB: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static let daylight = MosaicRGB(red: 0.39, green: 0.82, blue: 1)
    static let evening = MosaicRGB(red: 0.76, green: 0.35, blue: 1)

    func mixed(with other: MosaicRGB, amount: Double) -> MosaicRGB {
        let amount = min(1, max(0, amount))
        return MosaicRGB(red: red + (other.red - red) * amount,
                         green: green + (other.green - green) * amount,
                         blue: blue + (other.blue - blue) * amount)
    }
}

struct MosaicAppGroup: Codable, Equatable, Identifiable {
    enum Rule: String, Codable { case allExcept, only }

    var id: String
    var name: String
    var rule: Rule
    /// Exclusions for allExcept, inclusions for only.
    var appIDs: Set<String>

    func excludedApps(from allAppIDs: Set<String>) -> Set<String> {
        switch rule {
        case .allExcept: return appIDs
        case .only: return allAppIDs.subtracting(appIDs)
        }
    }

    mutating func setExcludedApps(_ excluded: Set<String>, allAppIDs: Set<String>) {
        switch rule {
        case .allExcept: appIDs = excluded
        case .only: appIDs = allAppIDs.subtracting(excluded)
        }
    }
}

struct MosaicTintSchedule: Codable, Equatable {
    enum Mode: String, CaseIterable, Codable {
        case off, timeOfDay, sunriseSunset
        var title: String {
            switch self {
            case .off: return "Off"
            case .timeOfDay: return "Time of day"
            case .sunriseSunset: return "Sunrise & sunset"
            }
        }
    }

    var mode: Mode = .off
    var dayColor = MosaicRGB.daylight
    var nightColor = MosaicRGB.evening
    var dayStrength: Double = 1
    var nightStrength: Double = 1
    var dayStartMinutes = 7 * 60
    var nightStartMinutes = 19 * 60
    var transitionMinutes = 60
    var locationName = ""
    var latitude: Double?
    var longitude: Double?

    func applying(to base: MosaicSettings, at date: Date, calendar: Calendar = .current) -> MosaicSettings {
        guard mode != .off, let nightAmount = nightAmount(at: date, calendar: calendar) else { return base }
        var result = base
        let color = dayColor.mixed(with: nightColor, amount: nightAmount)
        result.colorMode = .tinted
        result.tintRed = color.red
        result.tintGreen = color.green
        result.tintBlue = color.blue
        result.tintStrength = dayStrength + (nightStrength - dayStrength) * nightAmount
        return result
    }

    func nightAmount(at date: Date, calendar: Calendar = .current) -> Double? {
        switch mode {
        case .off: return nil
        case .timeOfDay:
            let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
            let minute = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
            return Self.nightAmount(minute: minute, sunrise: Double(dayStartMinutes), sunset: Double(nightStartMinutes),
                                    transition: Double(transitionMinutes), cycle: 24 * 60)
        case .sunriseSunset:
            guard let latitude, let longitude,
                  let times = MosaicSolarTimes.calculate(for: date, latitude: latitude, longitude: longitude, calendar: calendar) else { return nil }
            return Self.nightAmount(date: date, sunrise: times.sunrise, sunset: times.sunset,
                                    transition: TimeInterval(transitionMinutes * 60))
        }
    }

    private static func nightAmount(minute: Double, sunrise: Double, sunset: Double,
                                    transition: Double, cycle: Double) -> Double {
        func circularDistance(_ value: Double, _ target: Double) -> Double {
            let direct = value - target
            return ((direct + cycle / 2).truncatingRemainder(dividingBy: cycle) + cycle)
                .truncatingRemainder(dividingBy: cycle) - cycle / 2
        }
        let half = max(1, transition) / 2
        let sunriseDistance = circularDistance(minute, sunrise)
        if abs(sunriseDistance) <= half { return 0.5 - sunriseDistance / (2 * half) }
        let sunsetDistance = circularDistance(minute, sunset)
        if abs(sunsetDistance) <= half { return 0.5 + sunsetDistance / (2 * half) }
        let afterSunrise = ((minute - sunrise).truncatingRemainder(dividingBy: cycle) + cycle).truncatingRemainder(dividingBy: cycle)
        let daylightLength = ((sunset - sunrise).truncatingRemainder(dividingBy: cycle) + cycle).truncatingRemainder(dividingBy: cycle)
        return afterSunrise < daylightLength ? 0 : 1
    }

    private static func nightAmount(date: Date, sunrise: Date, sunset: Date, transition: TimeInterval) -> Double {
        let half = max(60, transition) / 2
        if abs(date.timeIntervalSince(sunrise)) <= half {
            return 0.5 - date.timeIntervalSince(sunrise) / (2 * half)
        }
        if abs(date.timeIntervalSince(sunset)) <= half {
            return 0.5 + date.timeIntervalSince(sunset) / (2 * half)
        }
        return date >= sunrise && date < sunset ? 0 : 1
    }
}

struct MosaicPreset: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var settings: MosaicSettings
    var appGroupID: String
    var tintSchedule: MosaicTintSchedule = MosaicTintSchedule()
}

struct MosaicPresetLibrary: Codable, Equatable {
    static let storageKey = "presetLibraryV1"
    static let focusPresetKey = "focusPresetID"
    static let changedNotification = Notification.Name("one.cwk.AppMosaic.configurationChanged")

    var version = 1
    var groups: [MosaicAppGroup]
    var presets: [MosaicPreset]
    var selectedPresetID: String

    static func initial(settings: MosaicSettings) -> MosaicPresetLibrary {
        let group = MosaicAppGroup(id: UUID().uuidString, name: "All Apps", rule: .allExcept,
                                   appIDs: settings.excludedApps)
        let preset = MosaicPreset(id: UUID().uuidString, name: "Default", settings: settings,
                                  appGroupID: group.id)
        return MosaicPresetLibrary(groups: [group], presets: [preset], selectedPresetID: preset.id)
    }

    static func load(from store: UserDefaults, fallback: MosaicSettings) -> MosaicPresetLibrary {
        guard let data = store.data(forKey: storageKey),
              var library = try? JSONDecoder().decode(MosaicPresetLibrary.self, from: data) else {
            let library = initial(settings: fallback)
            // Persist the generated identifiers immediately. Focus configurations
            // retain a preset ID and must still resolve before Options is ever opened.
            library.save(to: store)
            return library
        }
        let storedLibrary = library
        library.normalize(fallback: fallback)
        if library != storedLibrary { library.save(to: store) }
        return library
    }

    mutating func normalize(fallback: MosaicSettings = .defaults) {
        var seenGroups = Set<String>()
        groups = groups.filter { !$0.id.isEmpty && !$0.name.isEmpty && seenGroups.insert($0.id).inserted }
        if groups.isEmpty {
            groups = [MosaicAppGroup(id: UUID().uuidString, name: "All Apps", rule: .allExcept,
                                     appIDs: fallback.excludedApps)]
        }
        let validGroups = Set(groups.map(\.id))
        var seenPresets = Set<String>()
        presets = presets.filter { !$0.id.isEmpty && !$0.name.isEmpty && validGroups.contains($0.appGroupID) && seenPresets.insert($0.id).inserted }
        if presets.isEmpty {
            presets = [MosaicPreset(id: UUID().uuidString, name: "Default", settings: fallback,
                                    appGroupID: groups[0].id)]
        }
        if !presets.contains(where: { $0.id == selectedPresetID }) { selectedPresetID = presets[0].id }
    }

    func save(to store: UserDefaults) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(self) { store.set(data, forKey: Self.storageKey) }
        store.synchronize()
        DistributedNotificationCenter.default().post(name: Self.changedNotification, object: nil)
    }

    func activePresetID(in store: UserDefaults) -> String {
        if let focus = store.string(forKey: Self.focusPresetKey), presets.contains(where: { $0.id == focus }) { return focus }
        return selectedPresetID
    }

    func resolvedSettings(in store: UserDefaults, appIDs: Set<String>, at date: Date = Date(),
                          calendar: Calendar = .current) -> MosaicSettings {
        let id = activePresetID(in: store)
        guard let preset = presets.first(where: { $0.id == id }) ?? presets.first else { return .defaults }
        var settings = preset.settings
        if let group = groups.first(where: { $0.id == preset.appGroupID }) {
            settings.excludedApps = group.excludedApps(from: appIDs)
        }
        return preset.tintSchedule.applying(to: settings, at: date, calendar: calendar)
    }

    static func setFocusPreset(_ id: String?, in store: UserDefaults) {
        if let id { store.set(id, forKey: focusPresetKey) } else { store.removeObject(forKey: focusPresetKey) }
        store.synchronize()
        DistributedNotificationCenter.default().post(name: changedNotification, object: nil)
    }
}

struct MosaicSolarTimes: Equatable {
    let sunrise: Date
    let sunset: Date

    static func calculate(for date: Date, latitude: Double, longitude: Double,
                          calendar: Calendar = .current) -> MosaicSolarTimes? {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let local = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = local.year, let month = local.month, let day = local.day else { return nil }
        var localCalendar = calendar
        localCalendar.timeZone = calendar.timeZone
        let dayOfYear = localCalendar.ordinality(of: .day, in: .year, for: date) ?? 1
        guard let sunrise = event(year: year, month: month, day: day, dayOfYear: dayOfYear,
                                  latitude: latitude, longitude: longitude, sunrise: true),
              let sunset = event(year: year, month: month, day: day, dayOfYear: dayOfYear,
                                 latitude: latitude, longitude: longitude, sunrise: false) else { return nil }
        return MosaicSolarTimes(sunrise: sunrise, sunset: sunset)
    }

    private static func event(year: Int, month: Int, day: Int, dayOfYear: Int,
                              latitude: Double, longitude: Double, sunrise: Bool) -> Date? {
        func radians(_ value: Double) -> Double { value * .pi / 180 }
        func degrees(_ value: Double) -> Double { value * 180 / .pi }
        func normalized(_ value: Double, cycle: Double) -> Double {
            ((value.truncatingRemainder(dividingBy: cycle)) + cycle).truncatingRemainder(dividingBy: cycle)
        }
        let longitudeHour = longitude / 15
        let approximate = Double(dayOfYear) + ((sunrise ? 6 : 18) - longitudeHour) / 24
        let meanAnomaly = 0.9856 * approximate - 3.289
        var trueLongitude = meanAnomaly + 1.916 * sin(radians(meanAnomaly))
        trueLongitude += 0.020 * sin(radians(2 * meanAnomaly)) + 282.634
        trueLongitude = normalized(trueLongitude, cycle: 360)
        var rightAscension = degrees(atan(0.91764 * tan(radians(trueLongitude))))
        rightAscension = normalized(rightAscension, cycle: 360)
        rightAscension += floor(trueLongitude / 90) * 90 - floor(rightAscension / 90) * 90
        rightAscension /= 15
        let sinDeclination = 0.39782 * sin(radians(trueLongitude))
        let cosDeclination = cos(asin(sinDeclination))
        let cosHour = (cos(radians(90.833)) - sinDeclination * sin(radians(latitude))) /
            (cosDeclination * cos(radians(latitude)))
        guard (-1...1).contains(cosHour) else { return nil }
        var hourAngle = sunrise ? 360 - degrees(acos(cosHour)) : degrees(acos(cosHour))
        hourAngle /= 15
        let localMeanTime = hourAngle + rightAscension - 0.06571 * approximate - 6.622
        var utcHour = normalized(localMeanTime - longitudeHour, cycle: 24)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let midnight = utcCalendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        // Sunset in western longitudes often belongs to the next UTC date.
        if !sunrise && longitude < 0 && utcHour < 12 { utcHour += 24 }
        if sunrise && longitude > 0 && utcHour > 12 { utcHour -= 24 }
        return midnight.addingTimeInterval(utcHour * 3600)
    }
}
