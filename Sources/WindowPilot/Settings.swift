import AppKit
import Carbon
import SwiftUI

/// A key plus modifiers, stored with the label shown to the user (layout-dependent, captured at record time).
struct KeyShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt
    var key: String

    static let relevantFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    static let defaultHotKey = KeyShortcut(keyCode: UInt16(kVK_ANSI_D), modifiers: NSEvent.ModifierFlags.command.rawValue, key: "D")
    static let defaultSelectionKey = KeyShortcut(keyCode: UInt16(kVK_Tab), modifiers: 0, key: "⇥")

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.relevantFlags) }

    /// Display string in the standard macOS order, e.g. "⌃⌥⇧⌘D".
    var display: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + key
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && event.modifierFlags.intersection(Self.relevantFlags) == flags
    }

    func problem(global: Bool) -> String? {
        WindowLogic.shortcutProblem(keyCode: keyCode, command: flags.contains(.command), option: flags.contains(.option),
                                    control: flags.contains(.control), shift: flags.contains(.shift), global: global)
    }

    init(keyCode: UInt16, modifiers: UInt, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    init(event: NSEvent) {
        keyCode = event.keyCode
        modifiers = event.modifierFlags.intersection(Self.relevantFlags).rawValue
        key = Self.label(for: event)
    }

    private static let specialLabels: [Int: String] = [
        kVK_Tab: "⇥", kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "esc", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static func label(for event: NSEvent) -> String {
        if let special = specialLabels[Int(event.keyCode)] { return special }
        // The unmodified character, so ⌥/⇧ combinations still show the physical key.
        let base = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? ""
        return base.isEmpty ? "Key \(event.keyCode)" : base.uppercased()
    }
}

/// User preferences, persisted in the app's standard UserDefaults domain (dev.windowpilot.mac).
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var hotKey: KeyShortcut { didSet { save(hotKey, as: Keys.hotKey) } }
    @Published var selectionKey: KeyShortcut { didSet { save(selectionKey, as: Keys.selectionKey) } }
    /// True while a shortcut recorder is listening; the global hotkey is suspended meanwhile.
    @Published var recording = false
    /// Set by the app delegate when the system refuses to register the global hotkey.
    @Published var hotKeyError: String?

    private enum Keys {
        static let hotKey = "hotKey"
        static let selectionKey = "selectionKey"
    }

    private init() {
        hotKey = Self.load(Keys.hotKey) ?? .defaultHotKey
        selectionKey = Self.load(Keys.selectionKey) ?? .defaultSelectionKey
    }

    private static func load(_ name: String) -> KeyShortcut? {
        guard let data = UserDefaults.standard.data(forKey: name),
              let value = try? JSONDecoder().decode(KeyShortcut.self, from: data),
              value.problem(global: name == Keys.hotKey) == nil else { return nil }
        return value
    }

    private func save(_ value: KeyShortcut, as name: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: name)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                LabeledContent("呼出面板") {
                    ShortcutRecorder(shortcut: $settings.hotKey, global: true, other: settings.selectionKey,
                                     defaultValue: .defaultHotKey, settings: settings)
                }
                if let error = settings.hotKeyError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor).font(.callout).foregroundStyle(.secondary)
                }
                LabeledContent("进入／退出选择模式") {
                    ShortcutRecorder(shortcut: $settings.selectionKey, global: false, other: settings.hotKey,
                                     defaultValue: .defaultSelectionKey, settings: settings)
                }
            } header: {
                Text("快捷键")
            } footer: {
                Text("点击快捷键后按下新的组合键，按 esc 取消。全局快捷键需包含 ⌘、⌥ 或 ⌃；选择模式按键可以是 Tab、F1–F20，或带 ⌘、⌥、⌃ 的组合键。")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Click to record: the next key press (with modifiers) becomes the shortcut. Esc cancels.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut
    let global: Bool
    let other: KeyShortcut
    let defaultValue: KeyShortcut
    @ObservedObject var settings: AppSettings
    @State private var listening = false
    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button(action: toggle) {
                    Text(listening ? "按下快捷键…" : shortcut.display)
                        .font(.system(size: 12, weight: .medium, design: listening ? .default : .rounded))
                        .frame(minWidth: 96)
                }
                .buttonStyle(.bordered)
                .tint(listening ? .accentColor : nil)
                if shortcut != defaultValue {
                    Button { problem = nil; shortcut = defaultValue } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.borderless).help("恢复默认（\(defaultValue.display)）")
                }
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() { listening ? stop() : start() }

    private func start() {
        problem = nil
        listening = true
        settings.recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) && event.modifierFlags.intersection(KeyShortcut.relevantFlags).isEmpty {
                stop()
                return nil
            }
            let candidate = KeyShortcut(event: event)
            if let reason = candidate.problem(global: global) {
                problem = reason
            } else if candidate.keyCode == other.keyCode && candidate.flags == other.flags {
                problem = "与另一个快捷键重复"
            } else {
                problem = nil
                shortcut = candidate
            }
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        listening = false
        settings.recording = false
    }
}
