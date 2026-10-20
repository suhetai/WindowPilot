import AppKit
import ApplicationServices
import os
import ScreenCaptureKit
import SwiftUI

private let previewLog = Logger(subsystem: "dev.windowpilot.mac", category: "preview")

struct WindowItem: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let app: String
    let bundle: String
    var title: String
    let frame: CGRect
    let icon: NSImage?
    var captureWindow: SCWindow?
}

@MainActor
final class WindowStore: ObservableObject {
    @Published var query = "" { didSet { selected = 0; scheduleThumbnails() } }
    @Published var windows: [WindowItem] = []
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    @Published var selected = 0
    @Published var navigating = false
    @Published var loading = false
    @Published var message: String?
    @Published var accessibility = AXIsProcessTrusted()
    @Published var screenRecording = CGPreflightScreenCaptureAccess()
    @Published var previewErrors: [CGWindowID: String] = [:]
    /// Window awaiting close confirmation; while set, the launcher shows the confirmation dialog.
    @Published var pendingClose: WindowItem?
    /// Highlighted dialog button: `ConfirmChoice.close` or `.cancel`.
    @Published var confirmChoice = ConfirmChoice.cancel
    let columns = 3
    var dismiss: (() -> Void)?
    var openSettings: (() -> Void)?
    private var refreshTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var generation = UUID()

    var filtered: [WindowItem] {
        windows.filter { WindowLogic.matches(query: query, app: $0.app, title: $0.title, bundle: $0.bundle) }
    }

    func updatePermissions() {
        let trusted = AXIsProcessTrusted()
        let captureAllowed = CGPreflightScreenCaptureAccess()
        // Preflight values may lag behind a grant. Successful operations remain authoritative.
        if trusted && !accessibility { accessibility = true }
        if captureAllowed && !screenRecording {
            refresh()
        }
    }

    func refresh() {
        refreshTask?.cancel()
        thumbnailTask?.cancel()
        generation = UUID()
        let token = generation
        accessibility = AXIsProcessTrusted()
        screenRecording = CGPreflightScreenCaptureAccess()
        loading = true
        message = nil
        thumbnails = [:]
        previewErrors = [:]
        selected = 0
        // Metadata fallback lets the permission screen remain useful without a capture grant.
        let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        windows = rows.compactMap { row in
            guard let pid = row[kCGWindowOwnerPID as String] as? Int32,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let id = row[kCGWindowNumber as String] as? UInt32,
                  row[kCGWindowLayer as String] as? Int == 0,
                  let bounds = row[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 100, frame.height > 70,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { return nil }
            return WindowItem(id: id, pid: pid, app: app.localizedName ?? "Application",
                              bundle: app.bundleIdentifier ?? "", title: row[kCGWindowName as String] as? String ?? "",
                              frame: frame, icon: app.icon)
        }
        enrichAccessibilityTitles()
        refreshTask = Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                guard !Task.isCancelled, generation == token else { return }
                let captures = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
                screenRecording = true
                windows = windows.map { item in
                    var copy = item
                    copy.captureWindow = captures[item.id]
                    if let title = captures[item.id]?.title, !title.isEmpty { copy.title = title }
                    return copy
                }
                // Include windows in other Spaces that CGWindowList may omit.
                let known = Set(windows.map(\.id))
                for window in content.windows where !known.contains(window.windowID) {
                    guard window.windowLayer == 0, window.frame.width > 100, window.frame.height > 70,
                          let owner = window.owningApplication, owner.processID != ProcessInfo.processInfo.processIdentifier,
                          let app = NSRunningApplication(processIdentifier: owner.processID), app.activationPolicy == .regular else { continue }
                    windows.append(WindowItem(id: window.windowID, pid: owner.processID,
                                              app: app.localizedName ?? owner.applicationName, bundle: app.bundleIdentifier ?? "",
                                              title: window.title ?? "", frame: window.frame, icon: app.icon, captureWindow: window))
                }
                enrichAccessibilityTitles()
                loading = false
                scheduleThumbnails()
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                loading = false
                screenRecording = false
                let error = error as NSError
                message = "窗口捕获失败：\(error.domain) / \(error.code)：\(error.localizedDescription)"
            }
        }
    }

    private func axWindows(_ pid: pid_t) -> (AXError, [AXUIElement]) {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.5)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        return (result, value as? [AXUIElement] ?? [])
    }

    private func describe(_ element: AXUIElement) -> (String, CGRect) {
        var title: CFTypeRef?
        var position: CFTypeRef?
        var size: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)
        var point = CGPoint(x: -100_000, y: -100_000)
        var dimensions = CGSize.zero
        if let position, CFGetTypeID(position) == AXValueGetTypeID() {
            AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point)
        }
        if let size, CFGetTypeID(size) == AXValueGetTypeID() {
            AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions)
        }
        return (title as? String ?? "", CGRect(origin: point, size: dimensions))
    }

    private func enrichAccessibilityTitles() {
        for pid in Set(windows.map(\.pid)) {
            let (result, elements) = axWindows(pid)
            if result == .apiDisabled { accessibility = false; return }
            guard result == .success else { continue }
            accessibility = true
            let candidates = elements.map(describe)
            for index in windows.indices where windows[index].pid == pid && windows[index].title.isEmpty {
                let item = windows[index]
                if let match = WindowLogic.bestMatch(title: item.title, frame: item.frame, candidates: candidates) {
                    windows[index].title = candidates[match].0
                }
            }
        }
    }

    func stopCapture() {
        generation = UUID()
        refreshTask?.cancel()
        thumbnailTask?.cancel()
        thumbnails = [:]
    }

    private func scheduleThumbnails() {
        thumbnailTask?.cancel()
        let items = filtered
        let token = generation
        thumbnailTask = Task {
            // Debounce typing and capture only matching windows, one at a time.
            try? await Task.sleep(nanoseconds: 120_000_000)
            for item in items {
                guard !Task.isCancelled, generation == token else { return }
                guard thumbnails[item.id] == nil else { continue }
                // ScreenCaptureKit only renders windows on the current Space (other windows fail with
                // -3811), so off-screen windows use the window server's retained backing store instead.
                guard let window = item.captureWindow, window.isOnScreen else {
                    let image = await Self.backingStoreImage(item.id)
                    guard !Task.isCancelled, generation == token else { return }
                    if let image { thumbnails[item.id] = image; continue }
                    previewErrors[item.id] = isMinimized(item)
                        ? "窗口已最小化\n系统不保留最小化窗口的画面，恢复窗口后即可显示预览。"
                        : "窗口不在当前桌面\n系统未保留该窗口的画面（例如位于已断开的显示器上）。"
                    previewLog.notice("preview unavailable id=\(item.id) app=\(item.app, privacy: .public) reason=\(self.previewErrors[item.id]?.prefix(8) ?? "", privacy: .public)")
                    continue
                }
                let config = SCStreamConfiguration()
                config.width = 640
                config.height = max(1, Int(640 * window.frame.height / max(window.frame.width, 1)))
                config.showsCursor = false
                config.scalesToFit = true
                config.ignoreShadowsSingleWindow = true
                do {
                    let cg = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
                    guard !Task.isCancelled, generation == token else { return }
                    thumbnails[item.id] = NSImage(cgImage: cg, size: .zero)
                } catch {
                    guard !Task.isCancelled, generation == token else { return }
                    let error = error as NSError
                    // A visible window that still can't be captured has opted out of screen sharing.
                    previewErrors[item.id] = "该应用禁止截图\n\(error.domain) / \(error.code)：\(error.localizedDescription)"
                    previewLog.error("preview failed id=\(item.id) app=\(item.app, privacy: .public) error=\(error.domain, privacy: .public)/\(error.code)")
                }
            }
        }
    }

    private func isMinimized(_ item: WindowItem) -> Bool {
        let (result, elements) = axWindows(item.pid)
        guard result == .success,
              let index = WindowLogic.bestMatch(title: item.title, frame: item.frame, candidates: elements.map(describe)) else { return false }
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(elements[index], kAXMinimizedAttribute as CFString, &value)
        return (value as? Bool) ?? false
    }

    private static func backingStoreImage(_ id: CGWindowID) async -> NSImage? {
        let image = await Task.detached(priority: .userInitiated) { WindowServerCapture.image(of: id) }.value
        return image.map { NSImage(cgImage: $0, size: .zero) }
    }

    /// Nothing is highlighted until selection mode starts; the first key press only reveals the highlight.
    func move(dx: Int, dy: Int) {
        guard navigating else { enterSelection(); return }
        selected = WindowLogic.move(index: selected, count: filtered.count, columns: columns, dx: dx, dy: dy)
    }

    func toggleSelection() {
        if navigating { navigating = false } else { enterSelection() }
    }

    private func enterSelection() {
        guard !filtered.isEmpty else { return }
        selected = WindowLogic.step(selected, by: 0, count: filtered.count)
        navigating = true
    }

    /// Return activates the highlighted window; in search mode it first reveals the highlight.
    func selectCurrent() {
        guard navigating else { enterSelection(); return }
        guard filtered.indices.contains(selected) else { return }
        activate(filtered[selected])
    }

    // MARK: - Close window

    enum ConfirmChoice: Int { case close = 0, cancel = 1 }

    func requestClose() {
        guard navigating, filtered.indices.contains(selected) else { return }
        confirmChoice = .cancel
        pendingClose = filtered[selected]
    }

    func moveConfirm(by delta: Int) {
        confirmChoice = ConfirmChoice(rawValue: WindowLogic.step(confirmChoice.rawValue, by: delta, count: 2)) ?? .cancel
    }

    func resolveConfirm(_ choice: ConfirmChoice? = nil) {
        guard let item = pendingClose else { return }
        pendingClose = nil
        if (choice ?? confirmChoice) == .close { close(item) }
    }

    /// Presses the window's close button through Accessibility, then verifies the window really went away
    /// (apps may keep it open to ask about unsaved changes).
    private func close(_ item: WindowItem) {
        let (result, elements) = axWindows(item.pid)
        guard result == .success else {
            if result == .apiDisabled { accessibility = false }
            message = "读取目标窗口失败：AX \(result.rawValue)"
            return
        }
        guard let index = WindowLogic.bestMatch(title: item.title, frame: item.frame, candidates: elements.map(describe)) else {
            message = "无法唯一匹配该窗口（可能已关闭或位于其他桌面）。请刷新后重试。"
            return
        }
        var button: CFTypeRef?
        AXUIElementCopyAttributeValue(elements[index], kAXCloseButtonAttribute as CFString, &button)
        guard let button, CFGetTypeID(button) == AXUIElementGetTypeID() else {
            message = "该窗口没有可用的关闭按钮。"
            return
        }
        let pressed = AXUIElementPerformAction(unsafeBitCast(button, to: AXUIElement.self), kAXPressAction as CFString)
        guard pressed == .success else {
            message = "关闭窗口失败：AX \(pressed.rawValue)"
            return
        }
        let token = generation
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard generation == token else { return }
            let open = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
                .contains { ($0[kCGWindowNumber as String] as? UInt32) == item.id }
            if open {
                message = "“\(item.title.isEmpty ? item.app : item.title)”没有关闭，应用可能在询问是否保存，请切换到该窗口处理。"
                return
            }
            windows.removeAll { $0.id == item.id }
            thumbnails[item.id] = nil
            previewErrors[item.id] = nil
            if filtered.isEmpty { navigating = false }
            selected = WindowLogic.step(selected, by: 0, count: filtered.count)
        }
    }

    func activate(_ item: WindowItem) {
        let appElement = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(appElement, 1.0)
        let (result, elements) = axWindows(item.pid)
        guard result == .success else {
            if result == .apiDisabled { accessibility = false }
            message = "读取目标窗口失败：AX \(result.rawValue)" + (result == .apiDisabled ? "（系统拒绝当前版本的辅助功能访问）" : "（窗口可能已关闭或应用未响应）")
            return
        }
        accessibility = true
        let candidates = elements.map(describe)
        guard let index = WindowLogic.bestMatch(title: item.title, frame: item.frame, candidates: candidates) else {
            message = "无法唯一匹配该窗口（可能已关闭或名称重复）。请刷新后重试。"
            return
        }
        guard let app = NSRunningApplication(processIdentifier: item.pid) else {
            message = "目标应用已退出，请刷新窗口列表。"
            return
        }
        let target = elements[index]
        // Only touch what needs restoring: unhide() and un-minimizing bring the app's other windows forward too.
        var minimized: CFTypeRef?
        AXUIElementCopyAttributeValue(target, kAXMinimizedAttribute as CFString, &minimized)
        if (minimized as? Bool) == true {
            AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        if app.isHidden { app.unhide() }
        NSApp.yieldActivation(to: app)
        dismiss?()
        // Activate the app *for this window* first. Raising or focusing a window through Accessibility while
        // its app is inactive makes some apps (VS Code/Electron) activate themselves with their previous main
        // window, which pulls that window forward on another display.
        if !WindowFocus.focus(pid: item.pid, windowID: item.id) {
            // Public fallback: make the target main before activating, since activation raises the main window.
            AXUIElementPerformAction(target, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, target)
            app.activate(options: [])
        }
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, target)
        // Some Electron apps reorder their windows on activation; raise the selected one again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AXUIElementPerformAction(target, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, target)
        }
    }

    func openPermission(_ screen: Bool) {
        if screen { CGRequestScreenCaptureAccess() }
        else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        let pane = screen ? "Privacy_ScreenCapture" : "Privacy_Accessibility"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}
