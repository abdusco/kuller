import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 600),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "kuller Settings"
        window.minSize = NSSize(width: 620, height: 480)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc func openSettings(_ sender: Any?) {
        showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var width = ""
    @State private var height = ""
    @State private var message: String?
    @State private var recording: Recording?
    @State private var selectedAction: ShortcutAction? = .pick
    @State private var selectedBinding: Recording?
    @State private var selectedPreset: CropAspectRatio? = .original
    @State private var selectedTab = 0
    @State private var monitor: Any?

    private struct Recording: Equatable {
        let action: ShortcutAction
        let index: Int
    }

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $selectedTab) {
                presets.tabItem { Text("Crop Presets") }.tag(0)
                shortcuts.tabItem { Text("Shortcuts") }.tag(1)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
            HStack {
                Text("Changes are saved automatically.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") {
                    recording = nil
                    selectedBinding = nil
                    selectedPreset = .original
                    message = nil
                    preferences.reset()
                }
            }
        }
        .padding(20)
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard NSApp.keyWindow === SettingsWindowController.shared.window, let recording else { return event }
                // Escape ends recording; use the explicit Cancel Crop default
                // to restore Escape after clearing that action.
                if event.keyCode == 53 {
                    self.recording = nil
                    return nil
                }
                message = preferences.assign(KeyShortcut(event: event), to: recording.action, index: recording.index)
                self.recording = nil
                return nil
            }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            recording = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window === SettingsWindowController.shared.window {
                recording = nil
            }
        }
        .onChange(of: selectedTab) { _, _ in recording = nil; message = nil }
        .onChange(of: selectedAction) { _, action in
            if recording?.action != action { recording = nil }
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presets appear in this order in the crop menu and when cycling ratios. The first nine, excluding Free, have direct shortcuts.")
                .font(.callout).foregroundStyle(.secondary)
            List(selection: $selectedPreset) {
                ForEach(preferences.cropPresets, id: \.self) { preset in
                    HStack {
                        Text(preset.label)
                        Spacer()
                        if let digit = preferences.digitPresets.firstIndex(of: preset) {
                            Text(preferences.hint(ShortcutAction.allCases.first { $0.presetIndex == digit }!))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(preset)
                }
            }
            HStack {
                Button {
                    guard let selectedPreset else { return }
                    preferences.cropPresets.removeAll { $0 == selectedPreset }
                    self.selectedPreset = .original
                } label: { Image(systemName: "minus") }
                    .disabled(selectedPreset == nil || selectedPreset == .original || selectedPreset == .free)
                    .help("Remove selected preset")
                Divider().frame(height: 16)
                TextField("Width", text: $width).frame(width: 85)
                Text(":")
                TextField("Height", text: $height).frame(width: 85)
                Button { addRatio() } label: { Image(systemName: "plus") }
                    .help("Add ratio")
                Spacer()
                Button { movePreset(by: -1) } label: { Image(systemName: "arrow.up") }
                    .disabled(selectedPresetIndex == nil || selectedPresetIndex == 0)
                    .help("Move selected preset up")
                Button { movePreset(by: 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(selectedPresetIndex == nil || selectedPresetIndex == preferences.cropPresets.count - 1)
                    .help("Move selected preset down")
            }
            .buttonStyle(.borderless)
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(alignment: .top) { Divider() }
            Text("Original and Free are always available. Remove and add a ratio to replace it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select an action, then use + or − below to add or remove a shortcut. Click a shortcut to change it; Escape cancels recording.")
                .font(.callout).foregroundStyle(.secondary)
            List(selection: $selectedAction) {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(actionTitle(action))
                            Text(action.contexts.sorted().joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ForEach(Array(preferences.bindings(for: action).enumerated()), id: \.offset) { index, binding in
                            recordButton(action, index: index, label: binding.label)
                        }
                        if recording?.action == action,
                           recording?.index == preferences.bindings(for: action).count {
                            Text("Press keys…").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(action)
                }
            }
            HStack(spacing: 12) {
                Button {
                    guard let action = selectedAction else { return }
                    recording = Recording(action: action, index: preferences.bindings(for: action).count)
                    message = nil
                } label: { Image(systemName: "plus") }
                    .disabled(selectedAction == nil)
                    .accessibilityLabel("Add Shortcut")
                    .help("Add shortcut to selected action")
                Button {
                    guard let action = selectedAction else { return }
                    let index = selectedBinding?.action == action
                        ? selectedBinding!.index : preferences.bindings(for: action).count - 1
                    preferences.removeBinding(action, index: index)
                    recording = nil
                    selectedBinding = nil
                } label: { Image(systemName: "minus") }
                    .disabled(selectedAction == nil || preferences.bindings(for: selectedAction ?? .pick).isEmpty)
                    .accessibilityLabel("Remove Shortcut")
                    .help("Remove selected shortcut, or the last shortcut in the selected row")
                Divider().frame(height: 16)
                if let selectedAction {
                    Text(actionTitle(selectedAction)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    guard let selectedAction else { return }
                    recording = nil
                    selectedBinding = nil
                    message = preferences.restoreBindings(for: selectedAction)
                } label: { Image(systemName: "arrow.counterclockwise") }
                    .disabled(selectedAction == nil)
                    .help("Restore selected action's defaults")
            }
            .buttonStyle(.borderless)
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(alignment: .top) { Divider() }
            Text("⌘, Settings · ⌘Q Quit · ⌘W Close · Esc Exit remain standard app commands outside cropping.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private func recordButton(_ action: ShortcutAction, index: Int, label: String) -> some View {
        Button(recording == Recording(action: action, index: index) ? "Press keys…" : label) {
            selectedAction = action
            selectedBinding = Recording(action: action, index: index)
            recording = Recording(action: action, index: index)
            message = nil
        }
        .overlay {
            if selectedBinding == Recording(action: action, index: index), selectedAction == action {
                RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 1)
            }
        }
    }

    private func actionTitle(_ action: ShortcutAction) -> String {
        guard let index = action.presetIndex else { return action.title }
        let ratio = preferences.digitPresets.indices.contains(index) ? preferences.digitPresets[index].label : "not assigned"
        return "Crop preset \(index + 1) (\(ratio))"
    }

    private var selectedPresetIndex: Int? {
        selectedPreset.flatMap { preferences.cropPresets.firstIndex(of: $0) }
    }

    private func movePreset(by offset: Int) {
        guard let index = selectedPresetIndex, preferences.cropPresets.indices.contains(index + offset) else { return }
        preferences.cropPresets.swapAt(index, index + offset)
    }

    private func addRatio() {
        guard let w = Double(width), let h = Double(height), w.isFinite, h.isFinite,
              w > 0, h > 0, (w / h).isFinite, w / h > 0 else {
            message = "Enter positive numbers for both width and height."
            return
        }
        let preset = CropAspectRatio.custom(width: w, height: h)
        guard !preferences.cropPresets.contains(preset) else {
            message = "That ratio is already in the list."
            return
        }
        preferences.cropPresets.append(preset)
        width = ""
        height = ""
        message = nil
    }
}
