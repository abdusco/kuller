import AppKit
import Combine

enum ShortcutAction: String, CaseIterable, Codable {
    case pick, reject, next, previous, crop, info, submit
    case openImage, preview, copy, selectAll
    case confirmCrop, cancelCrop, nextRatio, previousRatio, freeRatio
    case ratio1, ratio2, ratio3, ratio4, ratio5, ratio6, ratio7, ratio8, ratio9

    var title: String {
        switch self {
        case .pick: return "Pick / move to Picks"
        case .reject: return "Reject / move to Rejects"
        case .next: return "Next image"
        case .previous: return "Previous image"
        case .crop: return "Start crop"
        case .info: return "Image information"
        case .submit: return "Finish culling"
        case .openImage: return "Open selected image"
        case .preview: return "Quick Look"
        case .copy: return "Copy selected files"
        case .selectAll: return "Select all"
        case .confirmCrop: return "Confirm crop"
        case .cancelCrop: return "Cancel crop"
        case .nextRatio: return "Next crop preset"
        case .previousRatio: return "Previous crop preset"
        case .freeRatio: return "Free crop"
        default: return "Crop preset \(presetIndex! + 1)"
        }
    }

    var contexts: Set<String> {
        switch self {
        case .pick, .reject: return ["Culling", "Review"]
        case .next, .previous, .crop, .info, .submit: return ["Culling"]
        case .openImage, .preview, .copy, .selectAll: return ["Review"]
        default: return ["Crop"]
        }
    }

    var presetIndex: Int? {
        [.ratio1, .ratio2, .ratio3, .ratio4, .ratio5, .ratio6, .ratio7, .ratio8, .ratio9]
            .firstIndex(of: self)
    }

    var defaults: [KeyShortcut] {
        switch self {
        case .pick: return [.init(35, "P")]
        case .reject: return [.init(7, "X")]
        case .next: return [.init(38, "J"), .init(124, "→")]
        case .previous: return [.init(40, "K"), .init(123, "←")]
        case .crop: return [.init(8, "C")]
        case .info: return [.init(34, "I")]
        case .submit: return [.init(36, "↩", .command)]
        case .openImage: return [.init(36, "↩"), .init(76, "⌤")]
        case .preview: return [.init(49, "Space")]
        case .copy: return [.init(8, "C", .command)]
        case .selectAll: return [.init(0, "A", .command)]
        case .confirmCrop: return [.init(36, "↩"), .init(76, "⌤")]
        case .cancelCrop: return [.init(53, "Esc")]
        case .nextRatio: return [.init(24, "+", .option)]
        case .previousRatio: return [.init(27, "−", .option)]
        case .freeRatio: return [.init(29, "0", .option)]
        default:
            let keys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
            let index = presetIndex!
            return [.init(keys[index], "\(index + 1)", .option)]
        }
    }
}

struct KeyShortcut: Codable, Equatable {
    let keyCode: UInt16
    let key: String
    let modifiers: UInt

    static let modifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(_ keyCode: UInt16, _ key: String, _ flags: NSEvent.ModifierFlags = []) {
        self.keyCode = keyCode
        self.key = key
        modifiers = flags.intersection(Self.modifierMask).rawValue
    }

    init(event: NSEvent) {
        let names: [UInt16: String] = [36: "↩", 76: "⌤", 53: "Esc", 49: "Space",
                                     123: "←", 124: "→", 125: "↓", 126: "↑",
                                     51: "⌫", 117: "⌦", 48: "Tab"]
        self.init(event.keyCode, names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)",
                  event.modifierFlags)
    }

    var label: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        return (flags.contains(.control) ? "⌃" : "")
            + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "")
            + (flags.contains(.command) ? "⌘" : "") + key
    }

    func matches(_ event: NSEvent) -> Bool {
        keyCode == event.keyCode && modifiers == event.modifierFlags.intersection(Self.modifierMask).rawValue
    }

    func sameKey(as other: KeyShortcut) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }
}

final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    private let defaults: UserDefaults

    @Published var cropPresets: [CropAspectRatio] { didSet { save(cropPresets, key: "cropPresets") } }
    @Published var shortcuts: [String: [KeyShortcut]] { didSet { save(shortcuts, key: "shortcuts") } }

    init(defaults: UserDefaults = AppIdentity.preferences) {
        self.defaults = defaults
        let saved = defaults.data(forKey: "cropPresets")
            .flatMap { try? JSONDecoder().decode([CropAspectRatio].self, from: $0) }
        var presets: [CropAspectRatio] = []
        for preset in saved ?? CropAspectRatio.allCases {
            if (preset == .original || preset == .free || (preset.ratio?.isFinite == true && preset.ratio! > 0)),
               !presets.contains(preset) { presets.append(preset) }
        }
        if !presets.contains(.original) { presets.insert(.original, at: 0) }
        if !presets.contains(.free) { presets.append(.free) }
        cropPresets = presets
        shortcuts = defaults.data(forKey: "shortcuts")
            .flatMap { try? JSONDecoder().decode([String: [KeyShortcut]].self, from: $0) } ?? [:]
    }

    var digitPresets: [CropAspectRatio] { Array(cropPresets.filter { $0 != .free }.prefix(9)) }

    func bindings(for action: ShortcutAction) -> [KeyShortcut] { shortcuts[action.rawValue] ?? action.defaults }
    func matches(_ action: ShortcutAction, _ event: NSEvent) -> Bool { bindings(for: action).contains { $0.matches(event) } }
    func hint(_ action: ShortcutAction) -> String { bindings(for: action).map(\.label).joined(separator: " / ") }

    func assign(_ shortcut: KeyShortcut, to action: ShortcutAction, index: Int) -> String? {
        // These belong to the standard app menu and must remain available.
        let reserved = [KeyShortcut(43, ",", .command), KeyShortcut(12, "Q", .command),
                        KeyShortcut(13, "W", .command), KeyShortcut(4, "H", .command),
                        KeyShortcut(4, "H", [.command, .option])]
        if reserved.contains(where: { $0.sameKey(as: shortcut) }) || (shortcut.keyCode == 53 && action.contexts != ["Crop"]) {
            return "That shortcut is reserved for macOS window or app commands."
        }
        for other in ShortcutAction.allCases where !other.contexts.isDisjoint(with: action.contexts) {
            for (bindingIndex, binding) in bindings(for: other).enumerated() {
                if other == action && bindingIndex == index { continue }
                if binding.sameKey(as: shortcut) { return "Already used by \(other.title). Clear that binding first." }
            }
        }
        var bindings = bindings(for: action)
        if bindings.indices.contains(index) { bindings[index] = shortcut } else { bindings.append(shortcut) }
        shortcuts[action.rawValue] = bindings
        return nil
    }

    func removeBinding(_ action: ShortcutAction, index: Int) {
        var bindings = bindings(for: action)
        guard bindings.indices.contains(index) else { return }
        bindings.remove(at: index)
        shortcuts[action.rawValue] = bindings
    }

    func reset() {
        cropPresets = CropAspectRatio.allCases
        shortcuts = [:]
    }

    func restoreBindings(for action: ShortcutAction) -> String? {
        for other in ShortcutAction.allCases where other != action && !other.contexts.isDisjoint(with: action.contexts) {
            if action.defaults.contains(where: { candidate in bindings(for: other).contains { $0.sameKey(as: candidate) } }) {
                return "A default shortcut is already used by \(other.title). Clear that binding first."
            }
        }
        shortcuts.removeValue(forKey: action.rawValue)
        return nil
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
