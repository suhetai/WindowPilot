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
        print("PASS: 18 checks — search, aliases, grid navigation, and window matching")
    }
}
