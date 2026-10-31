import Realitizer
import RealitizerPreview
import SwiftUI
import simd

/// The player character: a small knight with a plumed helmet, cape, sword and shield.
/// Faces +z. Feet at y = 0. About 0.95 m tall so it fits inside a 1 m field tile.
func makeHero() throws -> ModelAssetDefinition {
    let materials = [
        material("tunic", [0.16, 0.32, 0.72]),
        material("steel", [0.78, 0.8, 0.86], roughness: 0.25, metallic: 0.9),
        material("skin", [0.98, 0.8, 0.66]),
        material("ink", [0.06, 0.05, 0.08], roughness: 0.3),
        material("leather", [0.42, 0.25, 0.13]),
        material("gold", [0.95, 0.72, 0.2], roughness: 0.3, metallic: 0.9),
        material("plume", [0.86, 0.14, 0.16]),
        material("cape", [0.7, 0.1, 0.14], doubleSided: true),
    ]

    func leg(_ side: Float) throws -> MeshData {
        try merge([
            MeshBuilder.cylinder(radius: 0.05, height: 0.2, segments: 12).moved([0, -0.1, 0]),
            MeshBuilder.box(size: [0.11, 0.09, 0.16]).moved([0, -0.26, 0.025]),
        ])
    }

    let torso = try MeshBuilder.revolve(
        profile: [[0, 0], [0.12, 0], [0.15, 0.12], [0.14, 0.26], [0, 0.26]], segments: 20)
        .recalculatingNormals(smoothingAngle: .pi / 2)
    let chest = try MeshBuilder.sphere(radius: 0.13, latitudeSegments: 10, longitudeSegments: 20)
        .moved([0, 0.17, 0.035], scale: [1.05, 0.85, 0.75])
    let head = try MeshBuilder.sphere(radius: 0.15, latitudeSegments: 14, longitudeSegments: 24)
        .moved([0, 0.1, 0])
    let eyes = try merge([
        MeshBuilder.sphere(radius: 0.022, latitudeSegments: 6, longitudeSegments: 10)
            .moved([-0.055, 0.09, 0.138], scale: [1, 1.5, 0.6]),
        MeshBuilder.sphere(radius: 0.022, latitudeSegments: 6, longitudeSegments: 10)
            .moved([0.055, 0.09, 0.138], scale: [1, 1.5, 0.6]),
    ])
    let helmet = try merge([
        MeshBuilder.revolve(
            profile: [[0.168, 0], [0.17, 0.05], [0.15, 0.13], [0.09, 0.19], [0, 0.21]], segments: 24)
            .recalculatingNormals(smoothingAngle: .pi / 2),
        // nose guard
        MeshBuilder.box(size: [0.03, 0.09, 0.03]).moved([0, -0.01, 0.165]),
    ]).moved([0, 0.1, 0])
    let plume = try MeshBuilder.sphere(radius: 0.06, latitudeSegments: 8, longitudeSegments: 12)
        .moved([0, 0.3, -0.05], rotation: .x(-0.5), scale: [0.5, 0.9, 2.0])
    let cape = try MeshBuilder.surface(uSegments: 8, vSegments: 6) { uv in
        let u = uv.x - 0.5, v = uv.y
        return [u * 0.3 * (1 + v * 0.5), 0.27 - v * 0.48, -0.12 - v * 0.1 - cos(u * .pi) * 0.03]
    }
    let sleeve = try MeshBuilder.cylinder(radius: 0.045, height: 0.2, segments: 10).moved([0, -0.1, 0])
    let pad = try MeshBuilder.sphere(radius: 0.075, latitudeSegments: 8, longitudeSegments: 12)
        .moved([0, 0.0, 0], scale: [1.1, 0.7, 1.1])
    let hand = try MeshBuilder.sphere(radius: 0.05, latitudeSegments: 8, longitudeSegments: 12)
    let blade = try merge([
        MeshBuilder.box(size: [0.04, 0.4, 0.012]).moved([0, 0.26, 0]),
        MeshBuilder.cone(radius: 0.028, height: 0.06, segments: 4)
            .moved([0, 0.49, 0], scale: [1, 1, 0.3]),
    ])
    let hilt = try merge([
        MeshBuilder.box(size: [0.15, 0.025, 0.035]).moved([0, 0.055, 0]),
        MeshBuilder.cylinder(radius: 0.016, height: 0.1, segments: 8).moved([0, 0.0, 0]),
        MeshBuilder.sphere(radius: 0.022, latitudeSegments: 6, longitudeSegments: 8).moved([0, -0.055, 0]),
    ])
    let shield = try MeshBuilder.cylinder(radius: 0.15, height: 0.03, segments: 24)
        .moved(.zero, rotation: .z(.pi / 2))
    let emblem = try merge([
        MeshBuilder.box(size: [0.02, 0.18, 0.04]),
        MeshBuilder.box(size: [0.02, 0.04, 0.16]).moved([0, 0.03, 0]),
    ])

    let swordHold = simd_quatf.x(1.1)
    var asset = ModelAssetDefinition(
        name: "Hero", materials: materials,
        parts: [
            part("pelvis", try MeshBuilder.box(size: [0.25, 0.1, 0.17]), "leather", at: [0, 0.36, 0]),
            part("legL", try leg(1), "leather", at: [0.07, -0.03, 0], parent: "pelvis"),
            part("legR", try leg(-1), "leather", at: [-0.07, -0.03, 0], parent: "pelvis"),
            part("torso", torso, "tunic", at: [0, 0.04, 0], parent: "pelvis"),
            part("chest", chest, "steel", parent: "torso"),
            part("cape", cape, "cape", parent: "torso"),
            part("head", head, "skin", at: [0, 0.27, 0], parent: "torso"),
            part("eyes", eyes, "ink", parent: "head"),
            part("helmet", helmet, "steel", parent: "head"),
            part("plume", plume, "plume", parent: "head"),
            part("armL", sleeve, "tunic", at: [0.17, 0.22, 0], parent: "torso"),
            part("padL", pad, "steel", parent: "armL"),
            part("handL", hand, "skin", at: [0, -0.22, 0], parent: "armL"),
            part("shield", shield, "steel", at: [0.07, 0.04, 0.02], parent: "handL"),
            part("emblem", emblem, "gold", at: [0.018, 0, 0], parent: "shield"),
            part("armR", sleeve, "tunic", at: [-0.17, 0.22, 0], parent: "torso"),
            part("padR", pad, "steel", parent: "armR"),
            part("handR", hand, "skin", at: [0, -0.22, 0], parent: "armR"),
            part("hilt", hilt, "gold", rotation: swordHold, parent: "handR"),
            part("blade", blade, "steel", parent: "hilt"),
        ])

    asset.clips = [
        try bakeClip("idle", asset: asset, duration: 1.6, loop: true) { t in
            let s = sin(t / 1.6 * 2 * .pi)
            return [
                "torso": offset("torso", in: asset, translation: [0, s * 0.008, 0]),
                "armL": offset("armL", in: asset, rotation: .x(s * 0.05)),
                "armR": offset("armR", in: asset, rotation: .x(-s * 0.05)),
            ]
        },
        try bakeClip("walk", asset: asset, duration: 0.5, loop: true) { t in
            let s = sin(t / 0.5 * 2 * .pi)
            return [
                "pelvis": offset("pelvis", in: asset, translation: [0, abs(s) * 0.025, 0]),
                "legL": offset("legL", in: asset, rotation: .x(s * 0.6)),
                "legR": offset("legR", in: asset, rotation: .x(-s * 0.6)),
                "armL": offset("armL", in: asset, rotation: .x(-s * 0.45)),
                "armR": offset("armR", in: asset, rotation: .x(s * 0.45)),
                "cape": offset("cape", in: asset, rotation: .x(-0.15 - abs(s) * 0.15)),
            ]
        },
    ]
    return try asset.validated()
}

#Preview("Hero") {
    ModelAssetPreview(asset: try! makeHero())
}
