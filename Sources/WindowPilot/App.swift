import AppKit
import Carbon
import Combine
import SwiftUI

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = WindowStore()
    let settings = AppSettings.shared
    private var panel: LauncherPanel!
    private var status: NSStatusItem!
    private var toggleItem: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var keyboardMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var hotKeyFailure: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Standard responder-chain edit commands are required even for a menu-bar app.
        let mainMenu = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
        panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Native translucent window material that follows the system light/dark appearance.
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.maskImage = Self.roundedMask(radius: LauncherView.cornerRadius)
        let host = NSHostingView(rootView: LauncherView(store: store, settings: settings))
        host.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            host.topAnchor.constraint(equalTo: material.topAnchor),
            host.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        panel.contentView = material
        panel.delegate = self
        store.dismiss = { [weak self] in self?.hide(restore: false) }
        store.openSettings = { [weak self] in self?.showSettings() }

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "WindowPilot")
        let menu = NSMenu()
        toggleItem = menu.addItem(withTitle: "搜索窗口", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开辅助功能设置", action: #selector(accessibilitySettings), keyEquivalent: "")
        menu.addItem(withTitle: "打开屏幕录制设置", action: #selector(screenSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 WindowPilot", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        status.menu = menu

        installHotKeyHandler()
        applyHotKey()
        // Re-register when the shortcut changes; suspend it while a recorder listens so it can be captured.
        settings.$hotKey.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyHotKey() }
        }.store(in: &subscriptions)
        settings.$recording.dropFirst().removeDuplicates().sink { [weak self] recording in
            DispatchQueue.main.async { recording ? self?.unregisterHotKey() : self?.applyHotKey() }
        }.store(in: &subscriptions)
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, self.panel.isKeyWindow else { return event }
            return self.handle(event) ? nil : event
        }
        show()
    }

    private func installHotKeyHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().toggle()
            }
            return noErr
        }, 1, &spec, pointer, &hotKeyHandler)
    }

    private func unregisterHotKey() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func applyHotKey() {
        unregisterHotKey()
        let shortcut = settings.hotKey
        toggleItem?.title = "搜索窗口  \(shortcut.display)"
        let id = EventHotKeyID(signature: 0x57504C54, id: 1)
        let result = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        hotKeyFailure = result == noErr ? nil : "\(shortcut.display) 注册失败（\(result)），可能已被其他应用占用。请换一个快捷键，或从菜单栏打开。"
        settings.hotKeyError = hotKeyFailure
    }

    @objc func showSettings() {
        if panel.isVisible { hide(restore: false) }
        if settingsWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "WindowPilot 设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func toggle() { panel.isVisible ? hide(restore: true) : show() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !panel.isVisible { show() }
        return true
    }

    private func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        store.query = ""
        store.navigating = false
        store.pendingClose = nil
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let width = min(960, frame.width - 32)
            let height = min(680, frame.height - 32)
            panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height), display: false)
        }
        store.refresh()
        if let hotKeyFailure { store.message = hotKeyFailure }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .launcherDidOpen, object: nil)
    }

    private func hide(restore: Bool) {
        store.pendingClose = nil
        panel.orderOut(nil)
        store.stopCapture()
        if restore { previousApp?.activate(options: []) }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard panel.isVisible else { return }
        hide(restore: false)
    }

    private func handle(_ event: NSEvent) -> Bool {
        if store.pendingClose != nil { handleConfirmation(event); return true }
        // Candidate navigation and Return belong to the input method while composing text.
        if !store.navigating, let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        if event.keyCode == 53 { hide(restore: true); return true }
        if settings.selectionKey.matches(event) { store.toggleSelection(); return true }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "r": store.refresh(); return true
            case ",": showSettings(); return true
            default: return false
            }
        }
        if event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option) { return false }
        switch event.keyCode {
        // Tab is swallowed even when it isn't the selection key, so focus never leaves the search field.
        case 48: return true
        case 123: store.move(dx: -1, dy: 0); return true
        case 124: store.move(dx: 1, dy: 0); return true
        case 125: store.move(dx: 0, dy: 1); return true
        case 126: store.move(dx: 0, dy: -1); return true
        case 36, 76: store.selectCurrent(); return true
        default: break
        }
        guard store.navigating else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "h": store.move(dx: -1, dy: 0)
        case "j": store.move(dx: 0, dy: 1)
        case "k": store.move(dx: 0, dy: -1)
        case "l": store.move(dx: 1, dy: 0)
        case "x": store.requestClose()
        case "/", "i": store.navigating = false
        default: break
        }
        return true
    }

    /// The confirmation dialog is modal: h/k/←/↑ move up, j/l/→/↓ move down, Return confirms, Esc cancels.
    private func handleConfirmation(_ event: NSEvent) {
        switch event.keyCode {
        case 53: store.resolveConfirm(.cancel); return
        case 36, 76: store.resolveConfirm(); return
        case 123, 126: store.moveConfirm(by: -1); return
        case 124, 125: store.moveConfirm(by: 1); return
        default: break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "h", "k": store.moveConfirm(by: -1)
        case "j", "l": store.moveConfirm(by: 1)
        default: break
        }
    }

    @objc private func accessibilitySettings() { store.openPermission(false) }
    @objc private func screenSettings() { store.openPermission(true) }
    @objc private func quit() { NSApp.terminate(nil) }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }
}

@main
enum WindowPilotMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
