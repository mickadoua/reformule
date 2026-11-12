import Foundation

enum Model: String, CaseIterable {
    case fable, opus, sonnet, haiku

    var label: String {
        switch self {
        case .fable: "Fable (le plus fin, ~10 s)"
        case .opus: "Opus"
        case .sonnet: "Sonnet"
        case .haiku: "Haiku"
        }
    }
}

enum Effort: String, CaseIterable {
    case low, medium, high

    var label: String {
        switch self {
        case .low: "Faible"
        case .medium: "Moyen"
        case .high: "Élevé"
        }
    }
}

enum Mode: String, CaseIterable {
    case rewrite, proofread

    var label: String { self == .rewrite ? "Corriger et reformuler" : "Corriger seulement" }

    var summary: String {
        self == .rewrite ? "Orthographe, grammaire, ponctuation et tournures plus naturelles" : "Orthographe, grammaire et ponctuation, en changeant le moins de mots possible"
    }

    var task: String {
        switch self {
        case .rewrite: "Tu corriges et reformules des textes : orthographe, grammaire, accords, ponctuation, tournures plus claires et naturelles."
        case .proofread: "Tu corriges des textes : orthographe, grammaire, accords, ponctuation. Ne reformule pas : change le moins de mots possible."
        }
    }
}

struct Options {
    let model: Model
    let effort: Effort
    let mode: Mode
}

@MainActor enum Settings {
    static let defaults = UserDefaults.standard

    static var model: Model {
        get { defaults.string(forKey: "model").flatMap(Model.init) ?? .opus }
        set { defaults.set(newValue.rawValue, forKey: "model") }
    }

    static var effort: Effort {
        get { defaults.string(forKey: "effort").flatMap(Effort.init) ?? .low }
        set { defaults.set(newValue.rawValue, forKey: "effort") }
    }

    static var mode: Mode {
        get { defaults.string(forKey: "mode").flatMap(Mode.init) ?? .rewrite }
        set { defaults.set(newValue.rawValue, forKey: "mode") }
    }

    static var hotKey: HotKey {
        get { defaults.data(forKey: "hotKey").flatMap { try? JSONDecoder().decode(HotKey.self, from: $0) } ?? .default }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "hotKey") }
    }

    static var options: Options { Options(model: model, effort: effort, mode: mode) }
}
