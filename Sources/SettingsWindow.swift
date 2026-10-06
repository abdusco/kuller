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
    @State private var monitor: Any?

    private struct Recording: Equatable {
        let action: ShortcutAction
        let index: Int
    }

    var body: some View {
        VStack(spacing: 12) {
            TabView {
                presets.tabItem { Text("Crop Presets") }
                shortcuts.tabItem { Text("Shortcuts") }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
            HStack {
                Text("Changes are saved automatically.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") {
                    recording = nil
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
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presets appear in this order in the crop menu and when cycling ratios. The first nine, excluding Free, have direct shortcuts.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(Array(preferences.cropPresets.enumerated()), id: \.element) { index, preset in
                    HStack {
                        Text(preset.label)
                        Spacer()
                        if let digit = preferences.digitPresets.firstIndex(of: preset) {
                            Text(preferences.hint(ShortcutAction.allCases.first { $0.presetIndex == digit }!))
                                .foregroundStyle(.secondary)
                        }
                        Button { preferences.cropPresets.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }
                            .disabled(index == 0)
                        Button { preferences.cropPresets.swapAt(index, index + 1) } label: { Image(systemName: "arrow.down") }
                            .disabled(index == preferences.cropPresets.count - 1)
                        Button { preferences.cropPresets.remove(at: index) } label: { Image(systemName: "minus.circle") }
                            .disabled(preset == .original || preset == .free)
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Width", text: $width).frame(width: 85)
                Text(":")
                TextField("Height", text: $height).frame(width: 85)
                Button("Add Ratio") { addRatio() }
                Spacer()
            }
            Text("Original and Free are always available. Remove and add a ratio to replace it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Click a shortcut to record keys. Escape cancels recording. Clear a binding with ×; + adds another.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ShortcutAction.allCases, id: \.self) { action in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(action.title)
                                Text(action.contexts.sorted().joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            ForEach(Array(preferences.bindings(for: action).enumerated()), id: \.offset) { index, binding in
                                recordButton(action, index: index, label: binding.label)
                                Button("×") {
                                    recording = nil
                                    preferences.removeBinding(action, index: index)
                                }.buttonStyle(.borderless)
                            }
                            recordButton(action, index: preferences.bindings(for: action).count, label: "+")
                            Button { preferences.shortcuts.removeValue(forKey: action.rawValue) } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }.buttonStyle(.borderless).help("Restore this action's defaults")
                        }
                        Divider()
                    }
                }
            }
            Text("⌘, Settings · ⌘Q Quit · ⌘W Close · Esc Exit remain standard app commands outside cropping.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private func recordButton(_ action: ShortcutAction, index: Int, label: String) -> some View {
        Button(recording == Recording(action: action, index: index) ? "Press keys…" : label) {
            recording = Recording(action: action, index: index)
            message = nil
        }
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
