import Foundation

@main struct ModelTests {
    static func main() {
        let suite = "one.cwk.AppMosaic.Tests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        precondition(MosaicSettings(store: store) == .defaults)
        var settings = MosaicSettings()
        settings.iconSize = 138; settings.spacing = 0.2; settings.edgeMargin = 0.04; settings.edgeFade = 0.15
        settings.frequency = 0.9; settings.fadeDuration = 2.7; settings.movement = .up; settings.scrollSpeed = 0.7
        settings.colorMode = .tinted; settings.tintRed = 0.8; settings.tintStrength = 0.6; settings.excludedApps = ["a", "b"]
        settings.save(to: store)
        precondition(MosaicSettings(store: store) == settings)
        store.set(10000, forKey: "iconSize"); store.set(-7, forKey: "fadeDuration"); store.set(88, forKey: "movement")
        store.set(Double.infinity, forKey: "edgeFade")
        precondition(MosaicSettings(store: store).iconSize == 256)
        precondition(MosaicSettings(store: store).fadeDuration == 0.2)
        precondition(MosaicSettings(store: store).movement == .stationary)
        precondition(MosaicSettings(store: store).edgeFade == 0)
        store.removePersistentDomain(forName: suite)
        store.set(0.3, forKey: "frequency"); store.set(0.2, forKey: "scrollSpeed")
        store.set(["keep-excluded"], forKey: "excludedApps")
        let migrated = MosaicSettings(store: store)
        precondition(abs(migrated.changeInterval - 2.59) < 0.0001)
        precondition(abs(migrated.secondsPerCell - 52) < 0.0001)
        precondition(migrated.excludedApps == ["keep-excluded"])
        migrated.save(to: store)
        precondition(MosaicSettings(store: store) == migrated)
        MosaicSettings.defaults.save(to: store)
        precondition(MosaicSettings(store: store) == .defaults)
        var endpoints = MosaicSettings()
        endpoints.frequency = 0; endpoints.scrollSpeed = 0
        precondition(abs(endpoints.changeInterval - 30) < 0.0001 && abs(endpoints.secondsPerCell - 240) < 0.0001)
        endpoints.frequency = 1; endpoints.scrollSpeed = 1
        precondition(abs(endpoints.changeInterval - 0.25) < 0.0001 && abs(endpoints.secondsPerCell - 8) < 0.0001)

        store.removeObject(forKey: MosaicPresetLibrary.storageKey)
        let bootstrappedLibrary = MosaicPresetLibrary.load(from: store, fallback: settings)
        precondition(MosaicPresetLibrary.load(from: store, fallback: .defaults) == bootstrappedLibrary)
        precondition(bootstrappedLibrary.presets[0].settings == settings)
        var library = MosaicPresetLibrary.initial(settings: settings)
        library.save(to: store)
        precondition(MosaicPresetLibrary.load(from: store, fallback: .defaults) == library)
        let defaultGroup = library.groups[0]
        precondition(defaultGroup.rule == .allExcept && defaultGroup.appIDs == ["a", "b"])
        let appIDs: Set<String> = ["a", "b", "c", "d"]
        precondition(library.resolvedSettings(in: store, appIDs: appIDs).excludedApps == ["a", "b"])
        let workGroup = MosaicAppGroup(id: "work", name: "Work", rule: .only, appIDs: ["a", "c"])
        library.groups.append(workGroup)
        var workSettings = MosaicSettings.defaults; workSettings.iconSize = 72; workSettings.movement = .left
        let workPreset = MosaicPreset(id: "work-preset", name: "Work", settings: workSettings, appGroupID: workGroup.id)
        library.presets.append(workPreset); library.selectedPresetID = workPreset.id; library.save(to: store)
        let resolvedWork = library.resolvedSettings(in: store, appIDs: appIDs)
        precondition(resolvedWork.iconSize == 72 && resolvedWork.movement == .left)
        precondition(resolvedWork.excludedApps == ["b", "d"])
        MosaicPresetLibrary.setFocusPreset(library.presets[0].id, in: store)
        precondition(library.activePresetID(in: store) == library.presets[0].id)
        MosaicPresetLibrary.setFocusPreset(nil, in: store)
        precondition(library.activePresetID(in: store) == workPreset.id)

        var clockTint = MosaicTintSchedule()
        clockTint.mode = .timeOfDay; clockTint.dayStartMinutes = 7 * 60; clockTint.nightStartMinutes = 19 * 60
        clockTint.transitionMinutes = 60
        clockTint.dayColor = MosaicRGB(red: 1, green: 0, blue: 0)
        clockTint.nightColor = MosaicRGB(red: 0, green: 0, blue: 1)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        func time(_ hour: Int, _ minute: Int = 0) -> Date {
            utc.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: hour, minute: minute))!
        }
        precondition(clockTint.nightAmount(at: time(12), calendar: utc) == 0)
        precondition(clockTint.nightAmount(at: time(0), calendar: utc) == 1)
        precondition(abs(clockTint.nightAmount(at: time(7), calendar: utc)! - 0.5) < 0.0001)
        precondition(abs(clockTint.nightAmount(at: time(19), calendar: utc)! - 0.5) < 0.0001)
        let dayTint = clockTint.applying(to: .defaults, at: time(12), calendar: utc)
        precondition(dayTint.colorMode == .tinted && dayTint.tintRed == 1 && dayTint.tintBlue == 0)
        let nightTint = clockTint.applying(to: .defaults, at: time(0), calendar: utc)
        precondition(nightTint.tintRed == 0 && nightTint.tintBlue == 1)

        let dallas = MosaicSolarTimes.calculate(for: time(12), latitude: 32.7767, longitude: -96.7970, calendar: utc)!
        let sunriseHour = utc.component(.hour, from: dallas.sunrise)
        let sunsetHour = utc.component(.hour, from: dallas.sunset)
        precondition((11...13).contains(sunriseHour))
        precondition((0...2).contains(sunsetHour))
        precondition(dallas.sunrise < dallas.sunset)
        var solarTint = clockTint
        solarTint.mode = .sunriseSunset; solarTint.latitude = 32.7767; solarTint.longitude = -96.7970
        precondition(solarTint.nightAmount(at: dallas.sunrise, calendar: utc)! > 0.49)
        precondition(solarTint.nightAmount(at: dallas.sunrise, calendar: utc)! < 0.51)
        solarTint.latitude = nil
        precondition(solarTint.applying(to: settings, at: time(12), calendar: utc) == settings)
        var tokyo = Calendar(identifier: .gregorian); tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let tokyoNoon = tokyo.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 12))!
        let tokyoSolar = MosaicSolarTimes.calculate(for: tokyoNoon, latitude: 35.6764, longitude: 139.6500, calendar: tokyo)!
        precondition((4...6).contains(tokyo.component(.hour, from: tokyoSolar.sunrise)))
        precondition((17...19).contains(tokyo.component(.hour, from: tokyoSolar.sunset)))
        precondition(tokyoSolar.sunrise < tokyoNoon && tokyoNoon < tokyoSolar.sunset)

        let defaultGrid = MosaicLayout(settings: .defaults, width: 1920, height: 1080)
        precondition(abs(defaultGrid.pitch / defaultGrid.iconSize - 1.08) < 0.0001)
        precondition(defaultGrid.margin == 0)
        // No centered leftover gutter: the first/last icon either crosses the
        // screen edge or leaves at most half of the normal inter-icon gap.
        let firstLeft = defaultGrid.position(0).x - defaultGrid.iconSize / 2
        let lastRight = defaultGrid.position(defaultGrid.columns - 1).x + defaultGrid.iconSize / 2
        precondition(firstLeft <= defaultGrid.inset + 0.001)
        precondition(lastRight >= 1920 - defaultGrid.inset - 0.001)
        let ids = (0..<500).map(String.init)
        for direction in MosaicSettings.Movement.allCases {
            var config = MosaicSettings(); config.movement = direction
            for (width, height) in [(1920.0, 1080.0), (1080, 1920), (3440, 1440), (320, 180)] {
                let grid = MosaicLayout(settings: config, width: width, height: height)
                for t in stride(from: 0.0, through: 600, by: 0.25) {
                    let point = grid.position(0, after: t, secondsPerCell: 8)
                    if direction == .left || direction == .right {
                        precondition(point.x >= -grid.pitch / 2 - 0.001 && point.x <= -grid.pitch / 2 + grid.spanX + 0.001)
                    }
                    if direction == .up || direction == .down {
                        precondition(point.y >= -grid.pitch / 2 - 0.001 && point.y <= -grid.pitch / 2 + grid.spanY + 0.001)
                    }
                }
                if direction != .stationary {
                    let horizontal = direction == .left || direction == .right
                    let span = horizontal ? grid.spanX : grid.spanY
                    let viewport = horizontal ? grid.width : grid.height
                    let low = -grid.pitch / 2, high = low + span
                    precondition(low + grid.iconSize / 2 <= 0)
                    precondition(high - grid.iconSize / 2 >= viewport)
                    let point = grid.position(0, after: span / grid.pitch * 8, secondsPerCell: 8)
                    let initial = grid.position(0)
                    precondition(abs(point.x - initial.x) < 0.001 && abs(point.y - initial.y) < 0.001)
                }
            }
        }
        var roomy = MosaicSettings(); roomy.edgeMargin = 0.1; roomy.screenEdges = .wholeIcons
        let inset = MosaicLayout(settings: roomy, width: 1920, height: 1080)
        precondition(inset.margin == 108)
        precondition(inset.position(0).x - inset.iconSize / 2 >= 0)
        precondition(MosaicLayout(settings: .defaults, width: 0, height: 0).count == 0)

        var rotation = AppRotation(ids)
        precondition(Set((0..<500).compactMap { _ in rotation.next(avoiding: []) }).count == 500)
        var playback = MosaicPlayback(settings: .defaults, apps: ids, count: 80)
        var seen = Set(playback.slots.map(\.app))
        for time in 0..<1000 {
            if let change = playback.reserve(at: Double(time)) {
                let occupied = playback.slots.map(\.app) + playback.slots.compactMap(\.replacement)
                precondition(Set(occupied).count == occupied.count)
                seen.insert(change.app)
                playback.finish(index: change.index, app: change.app, at: Double(time))
            }
        }
        precondition(seen.count == 500)
        for count in [0, 1, 2] {
            var playback = MosaicPlayback(settings: .defaults, apps: (0..<count).map(String.init), count: 80)
            for i in 0..<100 {
                if let change = playback.reserve(at: Double(i)) { playback.finish(index: change.index, app: change.app, at: Double(i)) }
            }
            precondition(count == 0 ? playback.slots.isEmpty : playback.slots.count == 80)
        }
        print("PASS: settings and preset persistence, app groups, Focus override, clock/solar tinting, migration, bounds, pacing, wrapping, margins, shuffle coverage, duplicate avoidance, empty/small collections")
    }
}
