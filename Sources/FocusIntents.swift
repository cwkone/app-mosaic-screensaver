import AppIntents
import Foundation
import ScreenSaver

@available(macOS 14.0, *)
struct MosaicPresetEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "App Mosaic Preset")
    static var defaultQuery = MosaicPresetEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

@available(macOS 14.0, *)
struct MosaicPresetEntityQuery: EntityQuery {
    func entities(for identifiers: [MosaicPresetEntity.ID]) async throws -> [MosaicPresetEntity] {
        let wanted = Set(identifiers)
        return Self.entities().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [MosaicPresetEntity] {
        Self.entities()
    }

    private static func entities() -> [MosaicPresetEntity] {
        let store = MosaicIntentStore.defaults
        let library = MosaicPresetLibrary.load(from: store, fallback: MosaicSettings(store: store))
        return library.presets.map { MosaicPresetEntity(id: $0.id, name: $0.name) }
    }
}

@available(macOS 14.0, *)
struct SetMosaicPresetFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Set App Mosaic Preset"
    static var description = IntentDescription("Changes the App Mosaic preset while this Focus is active.")

    @Parameter(title: "Preset")
    var preset: MosaicPresetEntity?

    init() {}
    init(preset: MosaicPresetEntity?) { self.preset = preset }

    var displayRepresentation: DisplayRepresentation {
        if let preset { return DisplayRepresentation(title: "Use \(preset.name)") }
        return DisplayRepresentation(title: "Use Default App Mosaic Preset")
    }

    static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [Self] {
        let entities = (try? await MosaicPresetEntityQuery().suggestedEntities()) ?? []
        return entities.map { Self(preset: $0) }
    }

    func perform() async throws -> some IntentResult {
        let store = MosaicIntentStore.defaults
        if let preset {
            let library = MosaicPresetLibrary.load(from: store, fallback: MosaicSettings(store: store))
            guard library.presets.contains(where: { $0.id == preset.id }) else {
                throw SetFocusFilterIntentError.notFound
            }
            MosaicPresetLibrary.setFocusPreset(preset.id, in: store)
        } else {
            MosaicPresetLibrary.setFocusPreset(nil, in: store)
        }
        return .result()
    }
}

private enum MosaicIntentStore {
    static var defaults: UserDefaults {
        ScreenSaverDefaults(forModuleWithName: "one.cwk.AppMosaic")
            ?? UserDefaults(suiteName: "one.cwk.AppMosaic")
            ?? .standard
    }
}
