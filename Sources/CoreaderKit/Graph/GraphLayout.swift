import Foundation

/// Force-directed positions for a `NoteGraph` (Fruchterman–Reingold): connected nodes
/// pull together, all nodes push apart. Same graph and seed, same picture.
public enum GraphLayout {
    /// Positions keyed by node id, both coordinates in 0...1. The layout keeps its
    /// proportions: the longer side spans 0...1 and the shorter one is centred.
    ///
    /// Cost is nodes² per iteration; past a thousand nodes the iteration count is cut so
    /// the call stays in the low seconds. Call it off the main actor.
    public static func layout(_ graph: NoteGraph, iterations: Int = 250, seed: UInt64 = 1) -> [String: (x: Double, y: Double)] {
        let ids = graph.nodes.map(\.id)
        let count = ids.count
        guard count > 0 else { return [:] }
        guard count > 1 else { return [ids[0]: (x: 0.5, y: 0.5)] }

        var index: [String: Int] = [:]
        for (position, id) in ids.enumerated() where index[id] == nil { index[id] = position }
        let links: [(a: Int, b: Int, pull: Double)] = graph.edges.compactMap { edge in
            guard let a = index[edge.from], let b = index[edge.to], a != b else { return nil }
            // Structural edges hold clusters together; similarity edges pull by how alike.
            let pull = edge.kind == .similar ? 0.4 + 0.6 * edge.strength : 1
            return (a, b, pull)
        }

        var rng = SplitMix64(seed: seed)
        var x = (0..<count).map { _ in rng.unit() }
        var y = (0..<count).map { _ in rng.unit() }
        let k = (1 / Double(count)).squareRoot()   // ideal distance between neighbours
        let budget = 60_000_000 / (count * count)
        let steps = max(1, min(iterations, max(30, budget)))

        var dx = [Double](repeating: 0, count: count)
        var dy = [Double](repeating: 0, count: count)
        for step in 0..<steps {
            for i in 0..<count { dx[i] = 0; dy[i] = 0 }
            for i in 0..<count {
                for j in (i + 1)..<count {
                    var ex = x[i] - x[j], ey = y[i] - y[j]
                    var distance = (ex * ex + ey * ey).squareRoot()
                    if distance < 1e-9 {
                        // Coincident nodes: nudge apart in a direction that depends only on the pair.
                        ex = Double((i * 31 + j * 17) % 7 + 1) * 1e-4
                        ey = Double((i * 13 + j * 29) % 5 + 1) * 1e-4
                        distance = (ex * ex + ey * ey).squareRoot()
                    }
                    let force = k * k / distance
                    dx[i] += ex / distance * force; dy[i] += ey / distance * force
                    dx[j] -= ex / distance * force; dy[j] -= ey / distance * force
                }
            }
            for link in links {
                let ex = x[link.a] - x[link.b], ey = y[link.a] - y[link.b]
                let distance = max((ex * ex + ey * ey).squareRoot(), 1e-9)
                let force = distance * distance / k * link.pull
                dx[link.a] -= ex / distance * force; dy[link.a] -= ey / distance * force
                dx[link.b] += ex / distance * force; dy[link.b] += ey / distance * force
            }
            // Mild gravity keeps unconnected parts from drifting off to infinity.
            let temperature = 0.12 * (1 - Double(step) / Double(steps)) + 0.002
            for i in 0..<count {
                dx[i] += (0.5 - x[i]) * k * 0.6
                dy[i] += (0.5 - y[i]) * k * 0.6
                let length = max((dx[i] * dx[i] + dy[i] * dy[i]).squareRoot(), 1e-12)
                let move = min(length, temperature)
                x[i] += dx[i] / length * move
                y[i] += dy[i] / length * move
            }
        }

        let minX = x.min() ?? 0, maxX = x.max() ?? 1, minY = y.min() ?? 0, maxY = y.max() ?? 1
        let span = max(maxX - minX, maxY - minY, 1e-9)
        let offsetX = (1 - (maxX - minX) / span) / 2, offsetY = (1 - (maxY - minY) / span) / 2
        var result: [String: (x: Double, y: Double)] = [:]
        for (id, position) in index {
            result[id] = (x: min(max((x[position] - minX) / span + offsetX, 0), 1),
                          y: min(max((y[position] - minY) / span + offsetY, 0), 1))
        }
        return result
    }
}
