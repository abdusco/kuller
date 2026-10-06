import AppKit
import Foundation

@main
enum AppPreferencesTests {
    static func main() {
        let domain = "dev.abdus.kuller.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = AppPreferences(defaults: defaults)
        precondition(preferences.cropPresets == CropAspectRatio.allCases)
        precondition(preferences.bindings(for: .next).count == 2)

        let custom = CropAspectRatio.custom(width: 7, height: 5)
        preferences.cropPresets.insert(custom, at: 0)
        preferences.cropPresets.removeAll { $0 == .r16x9 }
        precondition(preferences.digitPresets.first == custom)
        precondition(custom.widthToHeight(imageAspect: 2) == 1.4)
        precondition(custom.cycled(forward: true, cases: preferences.cropPresets) == .original)

        let cases: [(String, KeyShortcut, ShortcutAction, Bool)] = [
            ("new binding", KeyShortcut(3, "F"), .pick, true),
            ("same context conflict", KeyShortcut(3, "F"), .reject, false),
            ("different context", KeyShortcut(3, "F"), .confirmCrop, true),
            ("reserved settings", KeyShortcut(43, ",", .command), .pick, false),
            ("reserved quit", KeyShortcut(12, "Q", .command), .pick, false),
            ("reserved exit", KeyShortcut(53, "Esc"), .pick, false),
            ("modifier distinction", KeyShortcut(3, "F", .shift), .reject, true),
        ]
        for (name, shortcut, action, accepted) in cases {
            precondition((preferences.assign(shortcut, to: action, index: 0) == nil) == accepted, name)
        }
        preferences.removeBinding(.next, index: 0)
        preferences.removeBinding(.next, index: 0)
        let loaded = AppPreferences(defaults: defaults)
        precondition(loaded.cropPresets == preferences.cropPresets, "Custom presets must survive relaunch")
        precondition(loaded.bindings(for: .pick) == [KeyShortcut(3, "F")], "Shortcuts must survive relaunch")
        precondition(loaded.bindings(for: .next).isEmpty, "Cleared shortcuts must stay cleared")

        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                    windowNumber: 0, context: nil, characters: "f", charactersIgnoringModifiers: "f",
                                    isARepeat: false, keyCode: 3)!
        precondition(loaded.matches(.pick, event))
        precondition(!loaded.matches(.reject, event), "Shift must match exactly")
        loaded.reset()
        let reset = AppPreferences(defaults: defaults)
        precondition(reset.cropPresets == CropAspectRatio.allCases)
        precondition(reset.bindings(for: .pick) == ShortcutAction.pick.defaults)
        print("AppPreferencesTests passed")
    }
}
