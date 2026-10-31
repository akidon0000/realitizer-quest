import Realitizer
import RealitizerPreview
import SwiftUI
import simd

/// The whole overworld as one asset: one merged mesh per material, built from `WorldMap`.
func makeField() throws -> ModelAssetDefinition {
    var ground: [MeshData] = []
    var trunks: [MeshData] = []
    var leaves: [MeshData] = []
    var rocks: [MeshData] = []
    var wood: [MeshData] = []
    var walls: [MeshData] = []
    var roofs: [MeshData] = []
    var stone: [MeshData] = []
    var blueRoofs: [MeshData] = []
    var lairStone: [MeshData] = []
    var lairGlow: [MeshData] = []

    let tileBox = try MeshBuilder.box(size: [1, 0.3, 1])
    let trunk = try MeshBuilder.cylinder(radius: 0.05, height: 0.24, segments: 6)
    let crown = try MeshBuilder.cone(radius: 0.24, height: 0.42, segments: 8)
    let roundTree = try MeshBuilder.sphere(radius: 0.17, latitudeSegments: 6, longitudeSegments: 9)
    let houseWall = try MeshBuilder.box(size: [0.26, 0.2, 0.24])
    let houseRoof = try MeshBuilder.cone(radius: 0.24, height: 0.2, segments: 4)

    func shade(_ rgb: SIMD3<Float>, _ x: Int, _ z: Int, _ amount: Float = 0.08) -> RGBAColor {
        let k = 1 + (hash01(x, z, 7) - 0.5) * 2 * amount
        return RGBAColor(sRGB: simd_clamp(rgb * k, .zero, .one))
    }

    for (p, tile) in WorldMap.allTiles where tile != .water {
        let x = Float(p.x), z = Float(p.y)
        let groundColor: SIMD3<Float> = switch tile {
        case .grass: [0.42, 0.72, 0.3]
        case .forest: [0.3, 0.56, 0.24]
        case .mountain: [0.46, 0.55, 0.32]
        case .road, .town, .castle: [0.82, 0.72, 0.5]
        case .lair: [0.3, 0.26, 0.3]
        case .bridge, .water: [0.3, 0.5, 0.7]
        }
        if tile != .bridge {
            let color = shade(groundColor, p.x, p.y)
            ground.append(try tileBox.moved([x, -0.15, z]).coloring { _ in color })
        }

        switch tile {
        case .forest:
            for i in 0..<3 {
                let ox = (hash01(p.x, p.y, i) - 0.5) * 0.6, oz = (hash01(p.x, p.y, i + 10) - 0.5) * 0.6
                let h = 0.8 + hash01(p.x, p.y, i + 20) * 0.5
                let base = SIMD3<Float>(x + ox, 0, z + oz)
                trunks.append(trunk.moved(base + [0, 0.12, 0]))
                let green = shade([0.16, 0.45, 0.2], p.x * 3 + i, p.y, 0.18)
                leaves.append(try crown.moved(base + [0, 0.36 * h, 0], scale: [1, h, 1]).coloring { _ in green })
                leaves.append(try crown.moved(base + [0, 0.55 * h, 0], scale: [0.75, h * 0.8, 0.75]).coloring { _ in green })
            }
        case .grass where hash01(p.x, p.y, 99) > 0.86:
            let base = SIMD3<Float>(x + 0.25, 0, z - 0.2)
            trunks.append(trunk.moved(base + [0, 0.12, 0]))
            let green = shade([0.3, 0.6, 0.22], p.x, p.y, 0.15)
            leaves.append(try roundTree.moved(base + [0, 0.34, 0]).coloring { _ in green })
        case .mountain:
            let h = 0.75 + hash01(p.x, p.y, 5) * 0.35
            let peak = try MeshBuilder.revolve(profile: [[0.62, 0], [0.5, h * 0.3], [0.34, h * 0.6], [0.16, h * 0.86], [0, h]], segments: 7)
                .noiseDisplaced(amplitude: 0.05, frequency: 3, seed: UInt64(p.x * 31 + p.y))
                .moved([x, -0.02, z], rotation: .y(hash01(p.x, p.y, 1) * 3))
                .recalculatingNormals(smoothingAngle: 0.3)
                .coloring { v in
                    let snow = min(max((v.position.y - h * 0.62) / (h * 0.12), 0), 1)
                    return RGBAColor(sRGB: [0.5, 0.45, 0.38]).interpolated(
                        to: RGBAColor(sRGB: [0.97, 0.97, 1.0]), fraction: snow)
                }
            rocks.append(peak)
        case .bridge:
            wood.append(try MeshBuilder.box(size: [1, 0.08, 0.7]).moved([x, -0.02, z]))
            wood.append(try MeshBuilder.box(size: [1, 0.12, 0.05]).moved([x, 0.08, z - 0.33]))
            wood.append(try MeshBuilder.box(size: [1, 0.12, 0.05]).moved([x, 0.08, z + 0.33]))
        case .town:
            for (dx, dz, turn) in [(-0.22, -0.2, 0.0), (0.22, -0.15, 0.4), (0.0, 0.24, -0.3)] as [(Float, Float, Float)] {
                let c = SIMD3<Float>(x + dx, 0, z + dz)
                walls.append(houseWall.moved(c + [0, 0.1, 0], rotation: .y(turn)))
                roofs.append(houseRoof.moved(c + [0, 0.3, 0], rotation: .y(turn + .pi / 4), scale: [1.05, 1, 1.05]))
            }
            let wellColor = RGBAColor(sRGB: [0.6, 0.6, 0.62])
            stone.append(try MeshBuilder.cylinder(radius: 0.07, height: 0.08, segments: 10).moved([x + 0.25, 0.04, z + 0.25]).coloring { _ in wellColor })
        case .castle:
            let grey = RGBAColor(sRGB: [0.78, 0.78, 0.8])
            stone.append(try MeshBuilder.box(size: [0.8, 0.32, 0.6]).moved([x, 0.16, z]).coloring { _ in grey })
            stone.append(try MeshBuilder.box(size: [0.34, 0.55, 0.34]).moved([x, 0.4, z - 0.05]).coloring { _ in grey })
            for (dx, dz) in [(-0.38, -0.28), (0.38, -0.28), (-0.38, 0.28), (0.38, 0.28)] as [(Float, Float)] {
                stone.append(try MeshBuilder.cylinder(radius: 0.1, height: 0.5, segments: 10).moved([x + dx, 0.25, z + dz]).coloring { _ in grey })
                blueRoofs.append(try MeshBuilder.cone(radius: 0.13, height: 0.24, segments: 10).moved([x + dx, 0.62, z + dz]))
            }
            blueRoofs.append(try MeshBuilder.cone(radius: 0.24, height: 0.34, segments: 4).moved([x, 0.84, z - 0.05], rotation: .y(.pi / 4)))
            let door = RGBAColor(sRGB: [0.35, 0.22, 0.12])
            stone.append(try MeshBuilder.box(size: [0.14, 0.18, 0.02]).moved([x, 0.09, z + 0.305]).coloring { _ in door })
        case .lair:
            for i in 0..<6 {
                let a = Float(i) / 6 * 2 * .pi
                let h: Float = 0.45 + hash01(i, 3) * 0.35
                lairStone.append(try MeshBuilder.cone(radius: 0.09, height: h, segments: 5)
                    .moved([x + sin(a) * 0.36, h / 2, z + cos(a) * 0.36], rotation: .z(sin(a) * 0.25)))
            }
            lairStone.append(try MeshBuilder.cylinder(radius: 0.28, height: 0.06, segments: 12).moved([x, 0.03, z]))
            lairGlow.append(try MeshBuilder.cone(radius: 0.1, height: 0.42, segments: 4).moved([x, 0.27, z]))
            lairGlow.append(try MeshBuilder.cone(radius: 0.1, height: 0.2, segments: 4).moved([x, 0.0, z], rotation: .x(.pi)))
        default:
            break
        }
    }

    let water = try MeshBuilder.box(size: [Float(WorldMap.width) + 40, 0.1, Float(WorldMap.height) + 40])
        .moved([Float(WorldMap.width) / 2, -0.2, Float(WorldMap.height) / 2])
    var lairGlowMesh = try merge(lairGlow)
    lairGlowMesh = lairGlowMesh.moved(.zero)

    return try ModelAssetDefinition(
        name: "Overworld",
        materials: [
            material("ground", [1, 1, 1], roughness: 0.95, vertexColor: true),
            material("water", [0.18, 0.42, 0.78], roughness: 0.15, metallic: 0.2),
            material("trunk", [0.42, 0.28, 0.16]),
            material("leaves", [1, 1, 1], roughness: 0.85, vertexColor: true),
            material("rock", [1, 1, 1], roughness: 0.9, vertexColor: true),
            material("wood", [0.55, 0.36, 0.2]),
            material("wall", [0.96, 0.92, 0.82]),
            material("roof", [0.78, 0.25, 0.18]),
            material("stone", [1, 1, 1], roughness: 0.8, vertexColor: true),
            material("blueRoof", [0.2, 0.36, 0.78], roughness: 0.4),
            material("lairStone", [0.18, 0.14, 0.22], roughness: 0.7),
            material("lairGlow", [0.75, 0.3, 1.0], glow: 4),
        ],
        parts: [
            part("water", water, "water"),
            part("ground", try merge(ground), "ground"),
            part("trunks", try merge(trunks), "trunk"),
            part("leaves", try merge(leaves), "leaves"),
            part("mountains", try merge(rocks), "rock"),
            part("bridge", try merge(wood), "wood"),
            part("walls", try merge(walls), "wall"),
            part("roofs", try merge(roofs), "roof"),
            part("stone", try merge(stone), "stone"),
            part("blueRoofs", try merge(blueRoofs), "blueRoof"),
            part("lairStone", try merge(lairStone), "lairStone"),
            part("lairGlow", lairGlowMesh, "lairGlow"),
        ]
    ).validated()
}

enum StageTheme: Sendable { case plains, forest, lair }

/// The backdrop for battles: a floor disc and a curved sky wall behind the monster.
func makeBattleStage(_ theme: StageTheme) throws -> ModelAssetDefinition {
    let (floorA, floorB, skyTop, skyLow): (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) = switch theme {
    case .plains: ([0.4, 0.7, 0.3], [0.3, 0.55, 0.22], [0.25, 0.5, 0.92], [0.78, 0.9, 1.0])
    case .forest: ([0.24, 0.48, 0.2], [0.16, 0.34, 0.14], [0.2, 0.38, 0.5], [0.55, 0.75, 0.6])
    case .lair: ([0.22, 0.17, 0.25], [0.1, 0.07, 0.12], [0.06, 0.02, 0.1], [0.5, 0.12, 0.2])
    }
    let ringSurface = try MeshBuilder.surface(uSegments: 32, vSegments: 6) { uv in
        let a = uv.x * 2 * .pi, r = 0.3 + (1 - uv.y) * 8.7
        return [cos(a) * r, 0, -sin(a) * r]
    }
    // The ring surface cannot reach r = 0 without degenerate triangles; a thin disc fills the hole.
    let hub = try MeshBuilder.cylinder(radius: 0.32, height: 0.01, segments: 32).moved([0, -0.004, 0])
    let floor = try merge([ringSurface, hub]).coloring { v in
        let ring = 0.5 + 0.5 * sin(simd_length(SIMD2(v.position.x, v.position.z)) * 2.2)
        return RGBAColor(sRGB: floorA).interpolated(to: RGBAColor(sRGB: floorB), fraction: ring)
    }
    let sky = try MeshBuilder.surface(uSegments: 40, vSegments: 8) { uv in
        let a = .pi * 0.05 + uv.x * .pi * 0.9, r: Float = 9
        return [-cos(a) * r, uv.y * 9 - 0.1, -sin(a) * r]
    }.coloring { v in
        RGBAColor(sRGB: skyLow).interpolated(to: RGBAColor(sRGB: skyTop), fraction: min(max(v.position.y / 7, 0), 1))
    }

    var props: [MeshData] = []
    for i in 0..<14 {
        let a = .pi * 0.12 + Float(i) / 13 * .pi * 0.76
        let r: Float = 7 + hash01(i, 1) * 1.2
        let h: Float = 1 + hash01(i, 2) * 1.6
        switch theme {
        case .plains:
            props.append(try MeshBuilder.sphere(radius: 1.6, latitudeSegments: 8, longitudeSegments: 12)
                .moved([-cos(a) * r, -0.6, -sin(a) * r], scale: [1.6, h * 0.5, 1]))
        case .forest:
            props.append(try MeshBuilder.cone(radius: 0.7, height: h * 1.8, segments: 8)
                .moved([-cos(a) * r, h * 0.9, -sin(a) * r]))
        case .lair:
            props.append(try MeshBuilder.cone(radius: 0.5, height: h * 2.2, segments: 5)
                .moved([-cos(a) * r, h * 1.1, -sin(a) * r], rotation: .z(sin(a * 7) * 0.2)))
        }
    }
    let propColor: SIMD3<Float> = switch theme {
    case .plains: [0.28, 0.55, 0.25]
    case .forest: [0.1, 0.3, 0.14]
    case .lair: [0.16, 0.1, 0.18]
    }

    var skyMaterial = material("sky", [1, 1, 1], vertexColor: true, doubleSided: true)
    skyMaterial.shading = .unlit
    return try ModelAssetDefinition(
        name: "Stage",
        materials: [
            material("floor", [1, 1, 1], roughness: 0.9, vertexColor: true, doubleSided: true),
            skyMaterial,
            material("props", propColor, roughness: 0.9),
        ],
        parts: [
            part("floor", floor, "floor"),
            part("sky", sky, "sky"),
            part("props", try merge(props), "props"),
        ]
    ).validated()
}

/// Battle effects: a sword slash, a fireball and a healing ring. The dragon's fire is a particle emitter.
func makeEffects() throws -> ModelAssetDefinition {
    let slash = try MeshBuilder.box(size: [0.9, 0.03, 0.01])
    let fire = try merge([
        MeshBuilder.sphere(radius: 0.22, latitudeSegments: 10, longitudeSegments: 14)
            .noiseDisplaced(amplitude: 0.05, frequency: 6, seed: 1),
        MeshBuilder.cone(radius: 0.16, height: 0.4, segments: 8).moved([0, 0.22, 0]),
    ])
    let ring = try MeshBuilder.revolve(profile: [[0.35, 0], [0.42, 0.02], [0.42, 0.5], [0.35, 0.52]], segments: 32)
    var slashMaterial = material("slash", [1, 1, 1])
    slashMaterial.shading = .unlit
    slashMaterial.unlitToneMapping = false
    return try ModelAssetDefinition(
        name: "Effects",
        materials: [
            slashMaterial,
            material("fire", [1, 0.35, 0.05], glow: 2.5),
            material("heal", [0.4, 1, 0.6], glow: 2, doubleSided: true),
        ],
        parts: [
            part("slash", slash, "slash"),
            part("fire", fire, "fire"),
            part("heal", ring, "heal"),
        ]
    ).validated()
}

#Preview("Overworld") {
    ModelAssetPreview(asset: try! makeField())
}

#Preview("Stage") {
    ModelAssetPreview(asset: try! makeBattleStage(.lair))
}
