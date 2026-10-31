import simd

enum Tile: Character, Sendable {
    case water = "~"
    case grass = "."
    case forest = "\""
    case mountain = "^"
    case road = "="
    case bridge = "b"
    case town = "T"
    case castle = "C"
    case lair = "D"

    var isWalkable: Bool { self != .water && self != .mountain }
}

/// The overworld. Column = x (east), row = z (south). One tile is 1 m.
enum WorldMap {
    static let rows: [String] = [
        "~~~~~~~~~~~~~~~~~~~~",
        "~^^^^^~~~~~~^^^^^^^~",
        "~^\"\"..~~~~~^^^D\"^^^~",
        "~^\"\"T..~~~^^.\"\"\"..^~",
        "~^\"....=~~^\".\"\".\"\"^~",
        "~^..===.bb=.\"\"\".\"\".~",
        "~^.=...\"~~...=====.~",
        "~..=..\"\"~~\"\"=\"\".\"..~",
        "~.C=..\"\"~~\"..\"\"\"..^~",
        "~..===..~~..\"\"..^^^~",
        "~~.....\"~~...\"\"..^^~",
        "~~~...\"\"~~~..\"..~~~~",
        "~~~~..~~~~~~....~~~~",
        "~~~~~~~~~~~~~~~~~~~~",
    ]

    static let width = rows[0].count
    static let height = rows.count
    static let start = SIMD2<Int>(2, 9)

    static func tile(_ p: SIMD2<Int>) -> Tile {
        guard p.y >= 0, p.y < height, p.x >= 0, p.x < width else { return .water }
        let row = rows[p.y]
        return Tile(rawValue: row[row.index(row.startIndex, offsetBy: p.x)]) ?? .water
    }

    static var allTiles: [(SIMD2<Int>, Tile)] {
        (0..<height).flatMap { z in (0..<width).map { x in (SIMD2(x, z), tile(SIMD2(x, z))) } }
    }

    static func world(_ p: SIMD2<Int>) -> SIMD3<Float> { [Float(p.x), 0, Float(p.y)] }
}
