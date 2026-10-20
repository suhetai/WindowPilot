import Foundation
import CoreGraphics

@main
enum WindowLogicChecks {
    static func main() {
        precondition(WindowLogic.matches(query: "vscode api", app: "Code", title: "api — workspace", bundle: "com.microsoft.VSCode"))
        precondition(!WindowLogic.matches(query: "vscode web", app: "Code", title: "api", bundle: "com.microsoft.VSCode"))
        precondition(WindowLogic.matches(query: "CAFE", app: "Café", title: "", bundle: ""))
        precondition(WindowLogic.matches(query: "项目", app: "Code", title: "项目 — main", bundle: "com.microsoft.VSCode"))
        precondition(WindowLogic.matches(query: "  ", app: "Code", title: "", bundle: ""))
        precondition(WindowLogic.matches(query: "vscode", app: "Code - Insiders", title: "", bundle: "com.microsoft.VSCodeInsiders"))
        precondition(WindowLogic.move(index: 2, count: 8, columns: 3, dx: 1, dy: 0) == 2)
        precondition(WindowLogic.move(index: 6, count: 8, columns: 3, dx: -1, dy: 0) == 6)
        precondition(WindowLogic.move(index: 5, count: 8, columns: 3, dx: 0, dy: 1) == 7)
        precondition(WindowLogic.move(index: 1, count: 8, columns: 3, dx: 0, dy: -1) == 0)
        precondition(WindowLogic.move(index: 0, count: 0, columns: 3, dx: 0, dy: 1) == 0)
        precondition(WindowLogic.move(index: 4, count: 8, columns: 3, dx: 1, dy: 0) == 5)
        precondition(WindowLogic.move(index: 4, count: 8, columns: 3, dx: -1, dy: 0) == 3)
        let a = CGRect(x: 0, y: 0, width: 800, height: 600)
        let b = CGRect(x: 900, y: 0, width: 800, height: 600)
        precondition(WindowLogic.bestMatch(title: "Code", frame: b, candidates: [("Code", a), ("Code", b)]) == 1)
        precondition(WindowLogic.bestMatch(title: "Code", frame: a, candidates: [("Code", a), ("Code", a)]) == nil)
        precondition(WindowLogic.bestMatch(title: "Closed", frame: b, candidates: [("Other", a)]) == nil)
        precondition(WindowLogic.bestMatch(title: "", frame: b, candidates: [("Different", a), ("Unnamed", b)]) == 1)
        precondition(WindowLogic.bestMatch(title: "", frame: b, candidates: []) == nil)
        let tabA = CGRect(x: 0, y: 0, width: 280, height: 200)
        let tabB = CGRect(x: 294, y: 0, width: 280, height: 200)
        let tabC = CGRect(x: 0, y: 216, width: 280, height: 200)
        precondition(WindowLogic.wormRect(from: tabA, to: tabB, elapsed: 0) == tabA)
        precondition(WindowLogic.wormRect(from: tabA, to: tabB, elapsed: WindowLogic.wormDuration) == tabB)
        let stretchedRight = WindowLogic.wormRect(from: tabA, to: tabB, elapsed: 0.15)
        precondition(stretchedRight.maxX > tabB.maxX - 20 && stretchedRight.minX < tabA.minX + 30, "leading edge first, trailing edge waits")
        precondition(stretchedRight.height < tabA.height, "squashes across the stretch")
        let stretchedLeft = WindowLogic.wormRect(from: tabB, to: tabA, elapsed: 0.15)
        precondition(stretchedLeft.minX < tabA.minX + 20 && stretchedLeft.maxX > tabB.maxX - 30)
        let stretchedDown = WindowLogic.wormRect(from: tabA, to: tabC, elapsed: 0.15)
        precondition(stretchedDown.maxY > tabC.maxY - 20 && stretchedDown.minY < tabA.minY + 30)
        var previousWidth: CGFloat = 0
        for step in stride(from: 0.22, through: WindowLogic.wormDuration, by: 0.02) {
            let width = WindowLogic.wormRect(from: tabA, to: tabB, elapsed: step).width
            precondition(previousWidth == 0 || width <= previousWidth + 0.01, "contracts monotonically once the lead lands")
            previousWidth = width
        }
        precondition(WindowLogic.step(1, by: 1, count: 2) == 1, "confirmation choice does not wrap")
        precondition(WindowLogic.step(1, by: -1, count: 2) == 0)
        precondition(WindowLogic.step(0, by: -1, count: 2) == 0)
        func problem(_ key: UInt16, cmd: Bool = false, opt: Bool = false, ctrl: Bool = false, shift: Bool = false, global: Bool = false) -> String? {
            WindowLogic.shortcutProblem(keyCode: key, command: cmd, option: opt, control: ctrl, shift: shift, global: global)
        }
        precondition(problem(48) == nil, "Tab is the default selection key")
        precondition(problem(48, shift: true) == nil)
        precondition(problem(0) != nil, "a plain letter would break typing in search")
        precondition(problem(0, shift: true) != nil)
        precondition(problem(0, opt: true) == nil)
        precondition(problem(15, cmd: true) != nil, "⌘R is refresh")
        precondition(problem(36) != nil && problem(53, ctrl: true) != nil, "Return and Esc are reserved")
        precondition(problem(2, cmd: true, global: true) == nil, "⌘D is the default hotkey")
        precondition(problem(2, global: true) != nil, "a global hotkey needs a modifier")
        precondition(problem(96, global: true) != nil)
        precondition(WindowLogic.splitTitle("Linux 配置 sftp服务.md — astro-cactus-blog", app: "Code") == ("Linux 配置 sftp服务.md", "astro-cactus-blog"))
        precondition(WindowLogic.splitTitle("● App.tsx — web-client — Visual Studio Code", app: "Code") == ("● App.tsx", "web-client"), "drops the app name")
        precondition(WindowLogic.splitTitle("my-page-title", app: "Google Chrome") == ("my-page-title", nil), "hyphens are not separators")
        precondition(WindowLogic.splitTitle("a – b — c", app: "X") == ("a", "b — c"))
        let ids: [CGWindowID] = Array(1...15)
        let searchBatches = WindowLogic.thumbnailBatches(ids: ids, loaded: [2, 11], columns: 3, selected: 0, navigating: false)
        precondition(searchBatches.immediate == [1, 3, 4, 5, 6, 7, 8, 9], "search mode loads only the first 9 visible windows first")
        precondition(searchBatches.deferred == [10, 12, 13, 14, 15], "remaining windows are deferred in search mode")
        let selectBatches = WindowLogic.thumbnailBatches(ids: ids, loaded: Set(1...9), columns: 3, selected: 13, navigating: true)
        precondition(selectBatches.deferred.isEmpty, "selection mode does not defer remaining windows")
        precondition(selectBatches.immediate.first == 14, "selected window is prioritized first")
        precondition(Set(selectBatches.immediate) == Set(10...15))
        print("PASS: 48 checks — search, aliases, grid navigation, window matching, worm highlight, dialog choice, shortcuts, titles, and thumbnail batching")
    }
}
