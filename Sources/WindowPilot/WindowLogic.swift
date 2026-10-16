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
}
