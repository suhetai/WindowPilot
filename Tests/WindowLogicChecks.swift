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
        print("PASS: 26 checks — search, aliases, grid navigation, window matching, and worm highlight")
    }
}
