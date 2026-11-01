import Realitizer
import RealitizerPreview
import SwiftUI
import simd

// Original monsters. Every model faces +z (toward the battle camera), feet at y = 0,
// and provides the clips "idle" (loop), "attack" (once) and "hurt" (once).

/// Mokorin: a round puff of pollen with two leaf ears.
func makeMokorin() throws -> ModelAssetDefinition {
    let body = try MeshBuilder.sphere(radius: 0.34, latitudeSegments: 20, longitudeSegments: 32)
        .noiseDisplaced(amplitude: 0.025, frequency: 7, seed: 3)
        .recalculatingNormals(smoothingAngle: .pi / 2)
        .coloring { v in
            let t = min(max((v.position.y + 0.34) / 0.68, 0), 1)
            return RGBAColor(sRGB: [1.0, 0.97, 0.75]).interpolated(
                to: RGBAColor(sRGB: [0.98, 0.82, 0.28]), fraction: t)
        }
    let leaf = try MeshBuilder.sphere(radius: 0.2, latitudeSegments: 8, longitudeSegments: 14)
        .moved([0, 0.17, 0], scale: [0.45, 1, 0.16])
    let eyeWhite = try MeshBuilder.sphere(radius: 0.07, latitudeSegments: 10, longitudeSegments: 16)
    let eyes = try merge([
        eyeWhite.moved([-0.12, 0.06, 0.28], scale: [1, 1.15, 0.7]),
        eyeWhite.moved([0.12, 0.06, 0.28], scale: [1, 1.15, 0.7]),
    ])
    let pupil = try MeshBuilder.sphere(radius: 0.035, latitudeSegments: 8, longitudeSegments: 12)
    let pupils = merge2(pupil.moved([-0.11, 0.05, 0.33]), pupil.moved([0.11, 0.05, 0.33]))
    let cheek = try MeshBuilder.sphere(radius: 0.04, latitudeSegments: 6, longitudeSegments: 10)
    let cheeks = merge2(
        cheek.moved([-0.2, -0.04, 0.26], scale: [1, 0.6, 0.5]),
        cheek.moved([0.2, -0.04, 0.26], scale: [1, 0.6, 0.5]))
    let foot = try MeshBuilder.sphere(radius: 0.08, latitudeSegments: 8, longitudeSegments: 12)
        .moved(.zero, scale: [1, 0.55, 1.3])

    var asset = ModelAssetDefinition(
        name: "Mokorin",
        materials: [
            material("fluff", [1, 1, 1], roughness: 0.9, vertexColor: true),
            material("leaf", [0.3, 0.7, 0.25], doubleSided: true),
            material("white", [0.98, 0.98, 0.96], roughness: 0.3),
            material("ink", [0.08, 0.06, 0.1], roughness: 0.2),
            material("blush", [1.0, 0.55, 0.55]),
            material("feet", [0.85, 0.6, 0.2]),
        ],
        parts: [
            part("body", body, "fluff", at: [0, 0.38, 0]),
            part("leafL", leaf, "leaf", at: [0.1, 0.28, 0], rotation: .z(-0.5), parent: "body"),
            part("leafR", leaf, "leaf", at: [-0.1, 0.28, 0], rotation: .z(0.5), parent: "body"),
            part("eyes", eyes, "white", parent: "body"),
            part("pupils", pupils, "ink", parent: "body"),
            part("cheeks", cheeks, "blush", parent: "body"),
            part("footL", foot, "feet", at: [0.15, 0.045, 0.06]),
            part("footR", foot, "feet", at: [-0.15, 0.045, 0.06]),
        ])
    asset.clips = [
        try bakeClip("idle", asset: asset, duration: 1.2, loop: true) { t in
            let s = sin(t / 1.2 * 2 * .pi)
            return [
                "body": offset("body", in: asset, translation: [0, abs(s) * 0.06, 0],
                               scale: [1 + 0.04 * (1 - abs(s)), 1 - 0.05 * (1 - abs(s)), 1 + 0.04 * (1 - abs(s))]),
                "leafL": offset("leafL", in: asset, rotation: .z(-s * 0.25)),
                "leafR": offset("leafR", in: asset, rotation: .z(s * 0.25)),
            ]
        },
        try bakeClip("attack", asset: asset, duration: 0.6, loop: false) { t in
            let k = sin(min(t / 0.6, 1) * .pi)
            return [
                "body": offset("body", in: asset, rotation: .x(k * 0.4), translation: [0, k * 0.25, k * 0.7])
            ]
        },
        try bakeClip("hurt", asset: asset, duration: 0.5, loop: false) { t in
            let k = sin(min(t / 0.5, 1) * .pi)
            return [
                "body": offset("body", in: asset, rotation: .x(-k * 0.35) * .z(sin(t * 40) * 0.15 * k),
                               translation: [0, 0, -k * 0.15], scale: [1 + k * 0.1, 1 - k * 0.12, 1])
            ]
        },
    ]
    return try asset.validated()
}

/// Kinokoro: a grumpy walking mushroom.
func makeKinokoro() throws -> ModelAssetDefinition {
    let stem = try MeshBuilder.revolve(
        profile: [[0, 0], [0.16, 0], [0.2, 0.12], [0.18, 0.34], [0.14, 0.42], [0, 0.42]], segments: 24)
        .recalculatingNormals(smoothingAngle: .pi / 2)
    let cap = try MeshBuilder.revolve(
        profile: [[0, -0.02], [0.4, -0.02], [0.46, 0.04], [0.42, 0.14], [0.3, 0.26], [0.14, 0.32], [0, 0.34]],
        segments: 32)
        .recalculatingNormals(smoothingAngle: .pi / 2)
    var spots: [MeshData] = []
    let spot = try MeshBuilder.sphere(radius: 0.06, latitudeSegments: 6, longitudeSegments: 10)
    for i in 0..<7 {
        let a = Float(i) / 7 * 2 * .pi + 0.3
        let ring: Float = i % 2 == 0 ? 0.42 : 0.27
        let h: Float = i % 2 == 0 ? 0.13 : 0.255
        let tilt: Float = i % 2 == 0 ? 0.9 : 0.55
        spots.append(spot.moved(
            [sin(a) * ring, h, cos(a) * ring],
            rotation: simd_quatf(angle: tilt, axis: [cos(a), 0, -sin(a)]), scale: [1, 0.35, 1]))
    }
    spots.append(spot.moved([0, 0.335, 0], scale: [1.2, 0.3, 1.2]))
    let eye = try MeshBuilder.sphere(radius: 0.035, latitudeSegments: 8, longitudeSegments: 10)
    let face = try merge([
        eye.moved([-0.07, 0.27, 0.17], scale: [1, 1.4, 0.6]),
        eye.moved([0.07, 0.27, 0.17], scale: [1, 1.4, 0.6]),
        MeshBuilder.box(size: [0.08, 0.018, 0.02]).moved([-0.075, 0.33, 0.17], rotation: .z(-0.4)),
        MeshBuilder.box(size: [0.08, 0.018, 0.02]).moved([0.075, 0.33, 0.17], rotation: .z(0.4)),
        MeshBuilder.box(size: [0.07, 0.015, 0.02]).moved([0, 0.19, 0.19]),
    ])
    let leg = try MeshBuilder.cylinder(radius: 0.055, height: 0.12, segments: 10).moved([0, -0.06, 0])
    let arm = try MeshBuilder.cylinder(radius: 0.035, height: 0.16, segments: 8).moved([0, -0.08, 0])

    var asset = ModelAssetDefinition(
        name: "Kinokoro",
        materials: [
            material("stem", [0.96, 0.9, 0.78], roughness: 0.8),
            material("cap", [0.62, 0.22, 0.6], roughness: 0.45),
            material("spots", [0.98, 0.96, 0.85]),
            material("ink", [0.08, 0.05, 0.08], roughness: 0.3),
        ],
        parts: [
            part("stem", stem, "stem", at: [0, 0.1, 0]),
            part("cap", cap, "cap", at: [0, 0.4, 0], parent: "stem"),
            part("spots", try merge(spots), "spots", parent: "cap"),
            part("face", face, "ink", parent: "stem"),
            part("armL", arm, "stem", at: [0.17, 0.24, 0], rotation: .z(0.7), parent: "stem"),
            part("armR", arm, "stem", at: [-0.17, 0.24, 0], rotation: .z(-0.7), parent: "stem"),
            part("legL", leg, "stem", at: [0.08, 0.12, 0]),
            part("legR", leg, "stem", at: [-0.08, 0.12, 0]),
        ])
    asset.clips = [
        try bakeClip("idle", asset: asset, duration: 0.9, loop: true) { t in
            let s = sin(t / 0.9 * 2 * .pi)
            return [
                "stem": offset("stem", in: asset, rotation: .z(s * 0.08), translation: [0, abs(s) * 0.04, 0]),
                "cap": offset("cap", in: asset, rotation: .z(-s * 0.1)),
                "legL": offset("legL", in: asset, translation: [0, max(s, 0) * 0.05, 0]),
                "legR": offset("legR", in: asset, translation: [0, max(-s, 0) * 0.05, 0]),
                "armL": offset("armL", in: asset, rotation: .x(s * 0.4)),
                "armR": offset("armR", in: asset, rotation: .x(-s * 0.4)),
            ]
        },
        try bakeClip("attack", asset: asset, duration: 0.6, loop: false) { t in
            let k = sin(min(t / 0.6, 1) * .pi)
            return [
                "stem": offset("stem", in: asset, rotation: .x(k * 0.6), translation: [0, k * 0.1, k * 0.55]),
                "armL": offset("armL", in: asset, rotation: .x(-k * 1.6)),
                "armR": offset("armR", in: asset, rotation: .x(-k * 1.6)),
            ]
        },
        try bakeClip("hurt", asset: asset, duration: 0.5, loop: false) { t in
            let k = sin(min(t / 0.5, 1) * .pi)
            return [
                "stem": offset("stem", in: asset, rotation: .x(-k * 0.3) * .z(sin(t * 40) * 0.12 * k),
                               translation: [0, 0, -k * 0.15]),
                "cap": offset("cap", in: asset, translation: [0, k * 0.08, 0]),
            ]
        },
    ]
    return try asset.validated()
}

/// Kokegame: a sleepy turtle whose shell is a mossy boulder, with clover and a flower growing on top.
func makeKokegame() throws -> ModelAssetDefinition {
    func ramp(_ x: Float) -> Float { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }
    // Height of the shell dome at radius r (before the z stretch), used to plant things on it.
    func domeHeight(_ r: Float) -> Float { 0.34 * sqrt(max(0, 1 - (r / 0.445) * (r / 0.445))) }

    let dome = try MeshBuilder.revolve(
        profile: [[0, 0], [0.4, 0], [0.44, 0.05], [0.41, 0.15], [0.33, 0.25], [0.19, 0.32], [0, 0.34]],
        segments: 40)
        .moved(.zero, scale: [1, 1, 1.18])
        .noiseDisplaced(amplitude: 0.03, frequency: 6, seed: 21)
    var rimStones: [MeshData] = []
    let stone = try MeshBuilder.sphere(radius: 0.07, latitudeSegments: 8, longitudeSegments: 12)
        .noiseDisplaced(amplitude: 0.015, frequency: 12, seed: 5)
    for i in 0..<16 {
        let a = Float(i) / 16 * 2 * .pi + hash01(i, 0, 4) * 0.2
        let s = 0.8 + hash01(i, 1, 4) * 0.4
        rimStones.append(stone.moved(
            [sin(a) * 0.42, 0.05, cos(a) * 0.42 * 1.18], rotation: .y(a), scale: [s * 1.1, s * 0.6, s * 0.8]))
    }
    let shell = try merge([dome] + rimStones)
        .recalculatingNormals(smoothingAngle: .pi / 3)
        .coloring { v in
            let p = v.position
            // Moss settles on the upper half with a ragged edge; the stone darkens toward the rim.
            let ragged = sin(p.x * 23 + 1.3) * sin(p.z * 19 - 0.7) * 0.04
            let moss = ramp((p.y - 0.14 + ragged) / 0.07)
            let stoneColor = RGBAColor(sRGB: [0.36, 0.34, 0.31]).interpolated(
                to: RGBAColor(sRGB: [0.56, 0.54, 0.49]), fraction: ramp(p.y / 0.2))
            let mossColor = RGBAColor(sRGB: [0.27, 0.43, 0.14]).interpolated(
                to: RGBAColor(sRGB: [0.46, 0.62, 0.22]), fraction: 0.5 + ragged * 12)
            return stoneColor.interpolated(to: mossColor, fraction: moss)
        }
    let belly = try MeshBuilder.sphere(radius: 0.38, latitudeSegments: 12, longitudeSegments: 24)
        .moved([0, 0.01, 0], scale: [1, 0.2, 1.16])

    var grass: [MeshData] = []
    let blade = try MeshBuilder.cone(radius: 0.012, height: 0.07, segments: 5)
    for i in 0..<34 {
        let a = hash01(i, 2, 9) * 2 * .pi
        let r = 0.05 + hash01(i, 3, 9) * 0.27
        let tilt = (hash01(i, 4, 9) - 0.5) * 0.7
        let h = 0.6 + hash01(i, 5, 9) * 0.7
        grass.append(blade.moved(
            [sin(a) * r, domeHeight(r) + 0.01, cos(a) * r * 1.18],
            rotation: simd_quatf(angle: tilt, axis: [cos(a), 0, -sin(a)]), scale: [1, h, 1]))
    }
    func clover(_ at: SIMD3<Float>, turn: Float) throws -> [MeshData] {
        let leaflet = try MeshBuilder.sphere(radius: 0.04, latitudeSegments: 6, longitudeSegments: 12)
        var meshes = [try MeshBuilder.cylinder(radius: 0.007, height: 0.08, segments: 6).moved(at + [0, 0.04, 0])]
        for k in 0..<3 {
            let a = Float(k) / 3 * 2 * .pi + turn
            meshes.append(leaflet.moved(
                at + [sin(a) * 0.035, 0.085, cos(a) * 0.035],
                rotation: .y(a) * .x(-0.35), scale: [1, 0.16, 0.85]))
        }
        return meshes
    }
    let clovers = try merge(clover([0.1, domeHeight(0.12), -0.12], turn: 0.4)
        + clover([0.2, domeHeight(0.22), 0.1], turn: 1.3))
    let flowerStem = try MeshBuilder.cylinder(radius: 0.008, height: 0.13, segments: 6).moved([0, 0.065, 0])
    let petal = try MeshBuilder.sphere(radius: 0.032, latitudeSegments: 6, longitudeSegments: 10)
    let petals = try merge((0..<5).map { k in
        let a = Float(k) / 5 * 2 * .pi
        return petal.moved([sin(a) * 0.033, 0.135, cos(a) * 0.033], rotation: .y(a) * .x(-0.3), scale: [0.7, 0.22, 1.1])
    })
    let pollen = try MeshBuilder.sphere(radius: 0.02, latitudeSegments: 6, longitudeSegments: 10)
        .moved([0, 0.14, 0], scale: [1, 0.6, 1])

    // Head with heavy, half-closed lids and a short horn beak.
    let lid = try MeshBuilder.sphere(radius: 0.038, latitudeSegments: 8, longitudeSegments: 12)
    let head = try merge([
        MeshBuilder.sphere(radius: 0.14, latitudeSegments: 16, longitudeSegments: 24).moved(.zero, scale: [1, 0.86, 1.1]),
        MeshBuilder.sphere(radius: 0.085, latitudeSegments: 10, longitudeSegments: 16).moved([0, -0.03, 0.1], scale: [1.1, 0.8, 1]),
        lid.moved([-0.088, 0.05, 0.085], rotation: .z(0.25), scale: [1.15, 0.55, 0.95]),
        lid.moved([0.088, 0.05, 0.085], rotation: .z(-0.25), scale: [1.15, 0.55, 0.95]),
    ]).recalculatingNormals(smoothingAngle: .pi / 2)
    let eye = try MeshBuilder.sphere(radius: 0.03, latitudeSegments: 8, longitudeSegments: 12)
    let eyes = merge2(eye.moved([-0.09, 0.03, 0.09], scale: [1, 0.9, 0.8]), eye.moved([0.09, 0.03, 0.09], scale: [1, 0.9, 0.8]))
    let glint = try MeshBuilder.sphere(radius: 0.008, latitudeSegments: 4, longitudeSegments: 6)
    let glints = merge2(glint.moved([-0.088, 0.036, 0.114]), glint.moved([0.092, 0.036, 0.114]))
    let nostril = try MeshBuilder.sphere(radius: 0.008, latitudeSegments: 4, longitudeSegments: 6)
    let beak = try merge([
        MeshBuilder.sphere(radius: 0.05, latitudeSegments: 8, longitudeSegments: 14).moved([0, -0.05, 0.16], scale: [1.2, 0.42, 0.6]),
        nostril.moved([-0.022, -0.005, 0.178]),
        nostril.moved([0.022, -0.005, 0.178]),
    ])
    let neck = try MeshBuilder.sphere(radius: 0.085, latitudeSegments: 10, longitudeSegments: 16)
        .moved(.zero, scale: [1, 0.95, 1.7])

    // Stubby legs hang from the hip; the foot sits on the ground.
    let nail = try MeshBuilder.sphere(radius: 0.02, latitudeSegments: 4, longitudeSegments: 8)
    let leg = try merge([
        MeshBuilder.cylinder(radius: 0.075, height: 0.13, segments: 12).moved([0, -0.06, 0]),
        MeshBuilder.sphere(radius: 0.085, latitudeSegments: 8, longitudeSegments: 14).moved([0, -0.13, 0.02], scale: [1.05, 0.5, 1.2]),
    ]).noiseDisplaced(amplitude: 0.006, frequency: 30, seed: 2)
    let nails = try merge((-1...1).map { k in nail.moved([Float(k) * 0.04, -0.14, 0.11 - abs(Float(k)) * 0.01], scale: [1, 0.7, 1.2]) })
    let tail = try MeshBuilder.cone(radius: 0.045, height: 0.13, segments: 8)

    var asset = ModelAssetDefinition(
        name: "Kokegame",
        materials: [
            material("shell", [1, 1, 1], roughness: 0.92, vertexColor: true),
            material("belly", [0.74, 0.66, 0.48], roughness: 0.8),
            material("skin", [0.52, 0.49, 0.33], roughness: 0.75),
            material("beak", [0.33, 0.28, 0.2], roughness: 0.4),
            material("ink", [0.05, 0.04, 0.04], roughness: 0.15),
            material("glint", [1, 1, 1], roughness: 0.1),
            material("nail", [0.84, 0.79, 0.64], roughness: 0.4),
            material("leaf", [0.3, 0.58, 0.2], doubleSided: true),
            material("petal", [0.98, 0.96, 0.92], roughness: 0.5, doubleSided: true),
            material("pollen", [0.98, 0.76, 0.18], roughness: 0.6),
        ],
        parts: [
            part("shell", shell, "shell", at: [0, 0.17, 0]),
            part("belly", belly, "belly", parent: "shell"),
            part("grass", try merge(grass), "leaf", parent: "shell"),
            part("clovers", clovers, "leaf", parent: "shell"),
            part("flower", flowerStem, "leaf", at: [-0.13, domeHeight(0.14), 0.05], parent: "shell"),
            part("petals", petals, "petal", parent: "flower"),
            part("pollen", pollen, "pollen", parent: "flower"),
            part("neck", neck, "skin", at: [0, 0.1, 0.46], rotation: .x(-0.35), parent: "shell"),
            part("head", head, "skin", at: [0, 0.04, 0.14], rotation: .x(0.35), parent: "neck"),
            part("eyes", eyes, "ink", parent: "head"),
            part("glints", glints, "glint", parent: "head"),
            part("beak", beak, "beak", parent: "head"),
            part("legFL", leg, "skin", at: [0.3, 0, 0.3], rotation: .z(0.15), parent: "shell"),
            part("legFR", leg, "skin", at: [-0.3, 0, 0.3], rotation: .z(-0.15), parent: "shell"),
            part("legBL", leg, "skin", at: [0.3, 0, -0.32], rotation: .z(0.15), parent: "shell"),
            part("legBR", leg, "skin", at: [-0.3, 0, -0.32], rotation: .z(-0.15), parent: "shell"),
            part("nailsFL", nails, "nail", parent: "legFL"),
            part("nailsFR", nails, "nail", parent: "legFR"),
            part("nailsBL", nails, "nail", parent: "legBL"),
            part("nailsBR", nails, "nail", parent: "legBR"),
            part("tail", tail, "skin", at: [0, 0.05, -0.52], rotation: .x(-.pi / 2 - 0.3), parent: "shell"),
        ])
    asset.clips = [
        try bakeClip("idle", asset: asset, duration: 2.4, loop: true) { t in
            let s = sin(t / 2.4 * 2 * .pi)
            let look = sin(t / 2.4 * 2 * .pi + 1)
            return [
                "shell": offset("shell", in: asset, scale: [1, 1 + s * 0.015, 1]),
                "neck": offset("neck", in: asset, rotation: .x(s * 0.06), translation: [0, 0, s * 0.015]),
                "head": offset("head", in: asset, rotation: .y(look * 0.2) * .x(-s * 0.05)),
                "flower": offset("flower", in: asset, rotation: .z(look * 0.18) * .x(s * 0.1)),
                "tail": offset("tail", in: asset, rotation: .z(s * 0.3)),
            ]
        },
        try bakeClip("attack", asset: asset, duration: 0.8, loop: false) { t in
            let u = t / 0.8
            let windUp = sin(ramp(u / 0.35) * .pi / 2) * (1 - ramp((u - 0.35) / 0.15))
            let k = sin(min(max((u - 0.3) / 0.6, 0), 1) * .pi)
            return [
                "shell": offset("shell", in: asset, rotation: .x(k * 0.18 - windUp * 0.1),
                                translation: [0, k * 0.08, k * 0.5 - windUp * 0.06]),
                "neck": offset("neck", in: asset, translation: [0, 0, -windUp * 0.1 + k * 0.05]),
                "head": offset("head", in: asset, rotation: .x(k * 0.35)),
                "flower": offset("flower", in: asset, rotation: .x(-k * 0.5)),
            ]
        },
        try bakeClip("hurt", asset: asset, duration: 0.6, loop: false) { t in
            let k = sin(min(t / 0.6, 1) * .pi)
            let tuck: Float = 1 - k * 0.45
            return [
                "shell": offset("shell", in: asset, rotation: .z(sin(t * 40) * 0.1 * k), translation: [0, -k * 0.03, -k * 0.1]),
                // Pulls its head and legs into the shell.
                "neck": offset("neck", in: asset, translation: [0, -k * 0.03, -k * 0.17], scale: [tuck, tuck, tuck]),
                "legFL": offset("legFL", in: asset, scale: [1, tuck, 1]),
                "legFR": offset("legFR", in: asset, scale: [1, tuck, 1]),
                "legBL": offset("legBL", in: asset, scale: [1, tuck, 1]),
                "legBR": offset("legBR", in: asset, scale: [1, tuck, 1]),
            ]
        },
    ]
    return try asset.validated()
}

/// Yoroigani: an armored crab with a spiked shell and heavy claws.
func makeYoroigani() throws -> ModelAssetDefinition {
    let shell = try MeshBuilder.sphere(radius: 0.4, latitudeSegments: 16, longitudeSegments: 28)
        .moved(.zero, scale: [1.25, 0.55, 1])
        .noiseDisplaced(amplitude: 0.02, frequency: 5, seed: 11)
        .recalculatingNormals(smoothingAngle: .pi / 3)
    var spikes: [MeshData] = []
    let spike = try MeshBuilder.cone(radius: 0.05, height: 0.14, segments: 6)
    for i in 0..<8 {
        let a = Float(i) / 8 * 2 * .pi
        spikes.append(spike.moved(
            [sin(a) * 0.32, 0.16, cos(a) * 0.24],
            rotation: simd_quatf(angle: 0.6, axis: [cos(a), 0, -sin(a)])))
    }
    spikes.append(spike.moved([0, 0.24, 0], scale: [1.4, 1.3, 1.4]))
    let stalk = try MeshBuilder.cylinder(radius: 0.022, height: 0.16, segments: 8)
    let stalks = merge2(
        stalk.moved([-0.1, 0.24, 0.28], rotation: .z(0.2)),
        stalk.moved([0.1, 0.24, 0.28], rotation: .z(-0.2)))
    let ball = try MeshBuilder.sphere(radius: 0.045, latitudeSegments: 8, longitudeSegments: 12)
    let eyeballs = merge2(ball.moved([-0.12, 0.33, 0.29]), ball.moved([0.12, 0.33, 0.29]))

    func claw(_ side: Float) throws -> MeshData {
        try merge([
            MeshBuilder.cylinder(radius: 0.05, height: 0.3, segments: 10)
                .moved([side * 0.1, 0, 0.08], rotation: simd_quatf(angle: side * -1.1, axis: [0.3, 0, 1])),
            MeshBuilder.sphere(radius: 0.15, latitudeSegments: 10, longitudeSegments: 16)
                .moved([side * 0.2, 0.02, 0.25], scale: [0.9, 0.75, 1.3]),
        ])
    }
    let pincer = try MeshBuilder.cone(radius: 0.06, height: 0.24, segments: 8)
        .moved([0, 0, 0.12], rotation: .x(.pi / 2), scale: [1, 1, 0.6])
    var legs: [MeshData] = []
    let legSegment = try MeshBuilder.cylinder(radius: 0.03, height: 0.34, segments: 8)
    for side: Float in [-1, 1] {
        for i in 0..<3 {
            let z = Float(i - 1) * 0.16 - 0.05
            legs.append(legSegment.moved([side * 0.48, 0.18, z], rotation: .z(side * 1.0)))
            legs.append(legSegment.moved([side * 0.62, 0.06, z], rotation: .z(side * 0.25)))
        }
    }

    var asset = ModelAssetDefinition(
        name: "Yoroigani",
        materials: [
            material("shell", [0.78, 0.26, 0.12], roughness: 0.35, metallic: 0.2),
            material("spike", [0.95, 0.85, 0.6], roughness: 0.4),
            material("dark", [0.45, 0.13, 0.08], roughness: 0.5),
            material("ink", [0.05, 0.05, 0.06], roughness: 0.15),
        ],
        parts: [
            part("shell", shell, "shell", at: [0, 0.36, 0]),
            part("spikes", try merge(spikes), "spike", parent: "shell"),
            part("stalks", stalks, "dark", parent: "shell"),
            part("eyeballs", eyeballs, "ink", parent: "shell"),
            part("clawL", try claw(1), "shell", at: [0.38, -0.05, 0.12], parent: "shell"),
            part("pincerL", pincer, "spike", at: [0.2, 0.08, 0.32], parent: "clawL"),
            part("clawR", try claw(-1), "shell", at: [-0.38, -0.05, 0.12], parent: "shell"),
            part("pincerR", pincer, "spike", at: [-0.2, 0.08, 0.32], parent: "clawR"),
            part("legs", try merge(legs), "dark"),
        ])
    asset.clips = [
        try bakeClip("idle", asset: asset, duration: 1.4, loop: true) { t in
            let s = sin(t / 1.4 * 2 * .pi)
            let snap = max(sin(t / 1.4 * 4 * .pi), 0)
            return [
                "shell": offset("shell", in: asset, rotation: .z(s * 0.05), translation: [s * 0.04, 0, 0]),
                "pincerL": offset("pincerL", in: asset, rotation: .x(-snap * 0.5)),
                "pincerR": offset("pincerR", in: asset, rotation: .x(-snap * 0.5)),
                "clawL": offset("clawL", in: asset, rotation: .y(s * 0.1)),
                "clawR": offset("clawR", in: asset, rotation: .y(s * 0.1)),
            ]
        },
        try bakeClip("attack", asset: asset, duration: 0.7, loop: false) { t in
            let k = sin(min(t / 0.7, 1) * .pi)
            return [
                "shell": offset("shell", in: asset, rotation: .x(k * 0.25), translation: [0, k * 0.05, k * 0.35]),
                "clawR": offset("clawR", in: asset, rotation: .x(-k * 0.6), translation: [0, k * 0.15, k * 0.35]),
                "pincerR": offset("pincerR", in: asset, rotation: .x(-k * 0.8)),
            ]
        },
        try bakeClip("hurt", asset: asset, duration: 0.5, loop: false) { t in
            let k = sin(min(t / 0.5, 1) * .pi)
            return [
                "shell": offset("shell", in: asset, rotation: .z(sin(t * 45) * 0.1 * k),
                                translation: [0, k * 0.05, -k * 0.12])
            ]
        },
    ]
    return try asset.validated()
}

func merge2(_ a: MeshData, _ b: MeshData) -> MeshData { try! merge([a, b]) }
func merge3(_ a: MeshData, _ b: MeshData, _ c: MeshData) -> MeshData { try! merge([a, b, c]) }

#Preview("Mokorin") { ModelAssetPreview(asset: try! makeMokorin()) }
#Preview("Kinokoro") { ModelAssetPreview(asset: try! makeKinokoro()) }
#Preview("Kokegame") { ModelAssetPreview(asset: try! makeKokegame()) }
#Preview("Yoroigani") { ModelAssetPreview(asset: try! makeYoroigani()) }
