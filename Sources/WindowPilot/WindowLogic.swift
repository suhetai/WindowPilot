import Foundation
import CoreGraphics

enum WindowLogic {
    static func matches(query: String, app: String, title: String, bundle: String) -> Bool {
        let aliases = bundle.hasPrefix("com.microsoft.VSCode")
            ? " vscode vs code visual studio code " : ""
        let haystack = (app + " " + title + " " + bundle + aliases)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return query.split(whereSeparator: { $0.isWhitespace }).allSatisfy {
            haystack.contains(String($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
        }
    }

    static func move(index: Int, count: Int, columns: Int, dx: Int, dy: Int) -> Int {
        guard count > 0, columns > 0 else { return 0 }
        let current = min(max(index, 0), count - 1)
        if dy != 0 { return min(max(current + dy * columns, 0), count - 1) }
        let next = current + dx
        guard next >= 0, next < count, next / columns == current / columns else { return current }
        return next
    }

    // A tied score is deliberately rejected: two identical titles must not select an arbitrary window.
    static func bestMatch(title: String, frame: CGRect, candidates: [(String, CGRect)]) -> Int? {
        let scores = candidates.enumerated().compactMap { index, candidate -> (Int, Double)? in
            let distance = abs(frame.minX - candidate.1.minX) + abs(frame.minY - candidate.1.minY)
                + abs(frame.width - candidate.1.width) + abs(frame.height - candidate.1.height)
            let sameTitle = !title.isEmpty && candidate.0 == title
            guard sameTitle || distance < 12 else { return nil }
            return (index, (sameTitle ? 10_000 : 0) - Double(distance))
        }.sorted { $0.1 > $1.1 }
        guard let best = scores.first else { return nil }
        if scores.count > 1 && abs(best.1 - scores[1].1) < 0.1 { return nil }
        return best.0
    }

    /// Moves a choice within `0..<count` without wrapping (used by the confirmation dialog).
    static func step(_ index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + delta, 0), count - 1)
    }

    // MARK: - Shortcut validation

    /// Return, keypad Enter, Esc, Delete, Forward Delete and the arrows always belong to the launcher.
    static let reservedKeyCodes: Set<UInt16> = [36, 76, 53, 51, 117, 123, 124, 125, 126]
    /// Keys that never insert text, so they can be used without a modifier: Tab and F1–F20.
    static let nonTypingKeyCodes: Set<UInt16> = [48, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
                                                 105, 107, 113, 106, 64, 79, 80, 90]
    /// ⌘A/Z/X/C/V (editing), ⌘R (refresh), ⌘, (settings) and ⌘Q are already taken inside the launcher.
    static let reservedCommandKeyCodes: Set<UInt16> = [0, 6, 7, 8, 9, 15, 43, 12]

    /// Returns a user-facing reason when a shortcut can't be used, or nil when it is acceptable.
    /// `global` is the system-wide launcher hotkey; otherwise it is a key handled inside the launcher.
    static func shortcutProblem(keyCode: UInt16, command: Bool, option: Bool, control: Bool, shift: Bool, global: Bool) -> String? {
        if reservedKeyCodes.contains(keyCode) { return "该按键已用于面板操作，请换一个" }
        let primary = command || option || control
        if global { return primary ? nil : "全局快捷键需要包含 ⌘、⌥ 或 ⌃" }
        if !primary && !nonTypingKeyCodes.contains(keyCode) { return "该按键会与搜索输入冲突，请搭配 ⌘、⌥ 或 ⌃ 使用" }
        if command && !option && !control && reservedCommandKeyCodes.contains(keyCode) { return "该快捷键已用于编辑、刷新或设置" }
        return nil
    }

    // Stretchy-worm highlight: on each axis the edge facing the destination leaves first and lands
    // with a slight overshoot; the far edge waits briefly, then accelerates to catch up.
    static let wormDuration = 0.42
    private static let wormLeadDuration = 0.22
    private static let wormTrailDelay = 0.10

    static func wormRect(from: CGRect, to: CGRect, elapsed: Double) -> CGRect {
        guard elapsed < wormDuration else { return to }
        guard elapsed > 0 else { return from }
        let t = elapsed
        let lead = easeOutBack(min(t / wormLeadDuration, 1))
        let trail = easeInOutCubic(min(max((t - wormTrailDelay) / (wormDuration - wormTrailDelay), 0), 1))
        func axis(_ fromMin: CGFloat, _ fromMax: CGFloat, _ toMin: CGFloat, _ toMax: CGFloat) -> (CGFloat, CGFloat) {
            let shift = (toMin + toMax) - (fromMin + fromMax)
            let pMin = shift < -0.5 ? lead : trail
            let pMax = shift > 0.5 ? lead : trail
            return (fromMin + (toMin - fromMin) * pMin, fromMax + (toMax - fromMax) * pMax)
        }
        let (minX, maxX) = axis(from.minX, from.maxX, to.minX, to.maxX)
        let (minY, maxY) = axis(from.minY, from.maxY, to.minY, to.maxY)
        // Slight squash across the stretch direction gives the gooey, elastic feel.
        let stretchX = max(0, (maxX - minX) - max(from.width, to.width))
        let stretchY = max(0, (maxY - minY) - max(from.height, to.height))
        let insetY = min(3, stretchX * 0.02)
        let insetX = min(3, stretchY * 0.02)
        return CGRect(x: minX + insetX, y: minY + insetY,
                      width: max(0, maxX - minX - insetX * 2), height: max(0, maxY - minY - insetY * 2))
    }

    private static func easeOutBack(_ x: Double) -> Double {
        let s = 0.9, p = x - 1
        return 1 + (s + 1) * p * p * p + s * p * p
    }

    private static func easeInOutCubic(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }
}
