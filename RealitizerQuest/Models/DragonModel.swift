import Realitizer
import RealitizerPreview
import SwiftUI
import simd

/// Varg, the fire dragon of the northern lair. Faces +z, feet at y = 0, about 2.6 m tall.
///
/// The torso, neck and tail are one skinned mesh bent by a spine of joints, so the neck curls and
/// the tail sways smoothly. Head, jaw, horns, wings and legs are rigid parts hanging from those joints.
/// The "mouth" socket marks where the game attaches its fire particles.
func makeDragon() throws -> ModelAssetDefinition {
    // MARK: Spine

    let neckCurve = Bezier(
        [0, 1.3, 0.55], [0, 1.78, 0.98], [0, 2.08, 0.72], [0, 2.42, 1.0])
    let tail: (Float) -> SIMD3<Float> = { t in
        [0.95 * pow(t, 2.2), 1.0 - 0.68 * t + 0.04 * t * t, -0.85 - 1.9 * t]
    }
    let joints: [(name: String, parent: String?, position: SIMD3<Float>)] = [
        ("hips", nil, [0, 1.05, -0.5]),
        ("chest", "hips", [0, 1.15, 0.35]),
        ("neck1", "chest", neckCurve.point(0.25)),
        ("neck2", "neck1", neckCurve.point(0.6)),
        ("head", "neck2", neckCurve.point(1)),
        ("tail1", "hips", tail(0.08)),
        ("tail2", "tail1", tail(0.35)),
        ("tail3", "tail2", tail(0.6)),
        ("tail4", "tail3", tail(0.85)),
    ]
    let jointPosition = Dictionary(uniqueKeysWithValues: joints.map { ($0.name, $0.position) })
    let rig = RigDefinition(
        id: rid("varg-rig"),
        joints: joints.map { joint in
            let local = joint.position - (joint.parent.map { jointPosition[$0]! } ?? .zero)
            return JointDefinition(
                id: rid(joint.name), parent: joint.parent.map(rid), restTransform: move(local))
        })
    /// Converts a rig-space point into the local space of a joint (rest joints carry no rotation).
    func local(_ p: SIMD3<Float>, _ joint: String) -> SIMD3<Float> { p - jointPosition[joint]! }

    // MARK: Torso, neck and tail (one skinned mesh)

    let torsoSections: [(z: Float, rx: Float, ry: Float, cy: Float)] = [
        (-1.0, 0.26, 0.26, 1.0), (-0.7, 0.4, 0.4, 1.03), (-0.35, 0.45, 0.47, 1.06), (0.05, 0.47, 0.52, 1.1),
        (0.4, 0.42, 0.5, 1.17), (0.65, 0.32, 0.38, 1.27), (0.8, 0.22, 0.26, 1.33),
    ]
    let torso = try MeshBuilder.loft(torsoSections.map {
        LoftSection(profile: ellipse($0.rx, $0.ry), transform: move([0, $0.cy, $0.z]))
    })
    let circle = try Profile2D.circle(radius: 1, segments: 18)
    let neck = try MeshBuilder.sweep(
        circle, along: (0...12).map { neckCurve.point(Float($0) / 12) },
        scales: (0...12).map { 0.31 - Float($0) / 12 * 0.15 })
    let tailMesh = try MeshBuilder.sweep(
        circle, along: (0...16).map { tail(Float($0) / 16) },
        scales: (0...16).map { 0.27 * pow(1 - Float($0) / 16, 1.1) + 0.03 })
    let hide = try merge([torso, neck, tailMesh])
        .recalculatingNormals(smoothingAngle: .pi / 3)
        .coloring(scaleColor)

    let bones: [(String, String)] = [
        ("hips", "chest"), ("chest", "neck1"), ("neck1", "neck2"), ("neck2", "head"),
        ("hips", "tail1"), ("tail1", "tail2"), ("tail2", "tail3"), ("tail3", "tail4"),
    ]
    let tailEnd = tail(1)
    let skin = try ModelGeometry(mesh: hide).binding(to: rig) { vertex in
        // Weight each vertex to the nearest bone, blending its two ends along the bone.
        var best: (distance: Float, weights: [JointWeight]) = (.infinity, [])
        for (a, b) in bones + [("tail4", "tail4")] {
            let pa = jointPosition[a]!, pb = a == b ? tailEnd : jointPosition[b]!
            let ab = pb - pa
            let t = simd_clamp(simd_dot(vertex.position - pa, ab) / simd_length_squared(ab), 0, 1)
            let d = simd_distance(vertex.position, pa + ab * t)
            if d < best.distance {
                best = a == b || t > 0.999 || t < 0.001
                    ? (d, [JointWeight(rid(t < 0.5 ? a : b), weight: 1)])
                    : (d, [JointWeight(rid(a), weight: 1 - t), JointWeight(rid(b), weight: t)])
            }
        }
        return best.weights
    }

    // MARK: Back spines, grouped by the joint that carries them

    var spines: [String: [MeshData]] = [:]
    let blade = try MeshBuilder.cone(radius: 0.07, height: 0.22, segments: 5).moved([0, 0.11, 0], scale: [0.35, 1, 1])
        .coloring { v in
            RGBAColor(sRGB: [0.35, 0.05, 0.04]).interpolated(
                to: RGBAColor(sRGB: [0.98, 0.78, 0.45]), fraction: simd_clamp(v.position.y / 0.22, 0, 1))
        }
    func addSpine(at p: SIMD3<Float>, tangent: SIMD3<Float>, up: SIMD3<Float>, size: Float, joint: String) {
        let t = simd_normalize(tangent)
        let n = simd_normalize(up - simd_dot(up, t) * t)
        let direction = simd_normalize(n - t * 0.6)
        let mesh = blade.moved(local(p, joint), rotation: simd_quatf(from: [0, 1, 0], to: direction), scale: .one * size)
        spines[joint, default: []].append(mesh)
    }
    for i in 0..<8 {
        let z = 0.68 - Float(i) * 0.22
        let section = interpolate(torsoSections, at: z)
        addSpine(at: [0, section.cy + section.ry - 0.04, z], tangent: [0, 0, 1], up: [0, 1, 0],
                 size: 1.1 - abs(z + 0.1) * 0.35, joint: z > -0.1 ? "chest" : "hips")
    }
    for i in 1..<7 {
        let s = Float(i) / 7
        let radius = 0.31 - s * 0.15
        let p = neckCurve.point(s), t = neckCurve.tangent(s)
        let back = simd_normalize(SIMD3<Float>(0, 0.3, -1))
        let n = simd_normalize(back - simd_dot(back, simd_normalize(t)) * simd_normalize(t))
        addSpine(at: p + n * (radius - 0.03), tangent: t, up: n, size: 0.8 - s * 0.35,
                 joint: s < 0.42 ? "neck1" : "neck2")
    }
    for i in 0..<9 {
        let s = 0.05 + Float(i) / 9 * 0.85
        let radius = 0.27 * pow(1 - s, 1.1) + 0.03
        let t = tail(s + 0.01) - tail(s)
        let joint = s < 0.35 ? "tail1" : s < 0.6 ? "tail2" : s < 0.85 ? "tail3" : "tail4"
        let up = SIMD3<Float>(0, 1, 0)
        let n = simd_normalize(up - simd_dot(up, simd_normalize(t)) * simd_normalize(t))
        addSpine(at: tail(s) + n * (radius - 0.02), tangent: t, up: n, size: 0.95 - s * 0.6, joint: joint)
    }
    let tailTip = tail(1), tailDirection = simd_normalize(tail(1) - tail(0.95))
    let spade = try MeshBuilder.cone(radius: 0.16, height: 0.42, segments: 4)
        .moved(local(tailTip, "tail4") + tailDirection * 0.15,
               rotation: simd_quatf(from: [0, 1, 0], to: tailDirection), scale: [1, 1, 0.16])
        .coloring { _ in RGBAColor(sRGB: [0.42, 0.06, 0.05]) }

    // MARK: Head

    let skullSections: [(z: Float, rx: Float, ry: Float, cy: Float)] = [
        (-0.2, 0.17, 0.17, 0.05), (-0.05, 0.2, 0.18, 0.07), (0.12, 0.17, 0.13, 0.06),
        (0.3, 0.13, 0.085, 0.05), (0.48, 0.105, 0.07, 0.045), (0.6, 0.075, 0.05, 0.04),
    ]
    let skull = try MeshBuilder.loft(skullSections.map {
        LoftSection(profile: ellipse($0.rx, $0.ry), transform: move([0, $0.cy, $0.z]))
    }).recalculatingNormals(smoothingAngle: .pi / 3).coloring(scaleColor)
    let browRidge = try MeshBuilder.sphere(radius: 0.06, latitudeSegments: 8, longitudeSegments: 12)
    let brows = try merge2(
        browRidge.moved([0.12, 0.17, 0.11], rotation: .z(-0.35), scale: [1.4, 0.45, 1.1]),
        browRidge.moved([-0.12, 0.17, 0.11], rotation: .z(0.35), scale: [1.4, 0.45, 1.1])
    ).coloring(scaleColor)

    let jawSections: [(z: Float, rx: Float, ry: Float, cy: Float)] = [
        (0, 0.15, 0.07, -0.02), (0.25, 0.12, 0.05, -0.03), (0.45, 0.095, 0.04, -0.03), (0.62, 0.06, 0.028, -0.025),
    ]
    let jaw = try MeshBuilder.loft(jawSections.map {
        LoftSection(profile: ellipse($0.rx, $0.ry), transform: move([0, $0.cy, $0.z]))
    }).recalculatingNormals(smoothingAngle: .pi / 3).coloring { _ in RGBAColor(sRGB: [0.5, 0.12, 0.08]) }
    let hinge = SIMD3<Float>(0, -0.05, -0.05)

    let fang = try MeshBuilder.cone(radius: 0.017, height: 0.06, segments: 5)
    var upperTeeth: [MeshData] = [], lowerTeeth: [MeshData] = []
    for side: Float in [-1, 1] {
        for i in 0..<6 {
            let z = 0.14 + Float(i) * 0.08
            let s = interpolate(skullSections, at: z)
            let length: Float = i == 4 ? 1.5 : 1
            upperTeeth.append(fang.moved([side * s.rx * 0.82, s.cy - s.ry * 0.85 - 0.02 * length, z],
                                         rotation: .x(.pi), scale: [1, length, 1]))
            let j = interpolate(jawSections, at: z - hinge.z - 0.03)
            lowerTeeth.append(fang.moved([side * j.rx * 0.75, j.cy + j.ry * 0.8 + 0.02, z - hinge.z - 0.03]))
        }
    }
    let maw = try MeshBuilder.sphere(radius: 1, latitudeSegments: 10, longitudeSegments: 16)
        .moved([0, -0.04, 0.22], scale: [0.1, 0.035, 0.3])
    let eyeBall = try MeshBuilder.sphere(radius: 0.038, latitudeSegments: 10, longitudeSegments: 14)
    let eyes = merge2(
        eyeBall.moved([0.148, 0.1, 0.13], scale: [0.6, 0.75, 1.1]),
        eyeBall.moved([-0.148, 0.1, 0.13], scale: [0.6, 0.75, 1.1]))
    let slit = try MeshBuilder.box(size: [0.006, 0.048, 0.012])
    let pupils = merge2(slit.moved([0.172, 0.1, 0.135]), slit.moved([-0.172, 0.1, 0.135]))
    let nostril = try MeshBuilder.sphere(radius: 0.016, latitudeSegments: 6, longitudeSegments: 8)
    let nostrils = merge2(nostril.moved([0.04, 0.085, 0.6]), nostril.moved([-0.04, 0.085, 0.6]))

    func horn(from base: SIMD3<Float>, _ c1: SIMD3<Float>, _ c2: SIMD3<Float>, to tip: SIMD3<Float>, radius: Float) throws -> MeshData {
        let curve = Bezier(base, c1, c2, tip)
        let samples = 10
        let length = (1...samples).reduce(Float(0)) {
            $0 + simd_distance(curve.point(Float($1) / Float(samples)), curve.point(Float($1 - 1) / Float(samples)))
        }
        return try MeshBuilder.sweep(
            Profile2D.circle(radius: 1, segments: 10), along: (0...samples).map { curve.point(Float($0) / Float(samples)) },
            scales: (0...samples).map { radius * (1 - Float($0) / Float(samples)) + 0.004 }
        ).coloring { v in
            let t = min(simd_distance(v.position, base) / length, 1)
            return RGBAColor(sRGB: [0.22, 0.12, 0.1]).interpolated(to: RGBAColor(sRGB: [0.95, 0.88, 0.7]), fraction: t)
        }
    }
    var horns: [MeshData] = []
    for side: Float in [-1, 1] {
        horns.append(try horn(from: [side * 0.11, 0.17, -0.06], [side * 0.2, 0.36, -0.24],
                              [side * 0.26, 0.38, -0.55], to: [side * 0.21, 0.3, -0.8], radius: 0.055))
        horns.append(try horn(from: [side * 0.16, 0.02, -0.1], [side * 0.24, 0.02, -0.2],
                              [side * 0.28, -0.02, -0.3], to: [side * 0.27, -0.06, -0.42], radius: 0.03))
    }
    horns.append(try horn(from: [0, 0.09, 0.47], [0, 0.14, 0.5], [0, 0.18, 0.5], to: [0, 0.21, 0.46], radius: 0.022))

    // MARK: Wings (rigid; the forearm folds on its own pivot)

    struct Wing { var arm: MeshData; var inner: MeshData; var forearm: MeshData; var membrane: MeshData; var elbow: SIMD3<Float> }
    func wing(_ s: Float) throws -> Wing {
        let elbow = SIMD3<Float>(s * 0.45, 0.42, -0.25)
        let wrist = SIMD3<Float>(s * 0.55, 0.35, -0.3)  // forearm-local
        let fingers: [SIMD3<Float>] = [
            [s * 0.75, 0.55, -0.35], [s * 0.85, -0.05, -0.55], [s * 0.6, -0.55, -0.7], [s * 0.2, -0.85, -0.65],
        ].map { wrist + $0 }
        func bone(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ r0: Float, _ r1: Float, lift: Float = 0.06) throws -> MeshData {
            let mid = (a + b) / 2 + [0, lift, 0]
            let curve = Bezier(a, mid, mid, b)
            return try MeshBuilder.sweep(
                Profile2D.circle(radius: 1, segments: 8), along: (0...8).map { curve.point(Float($0) / 8) },
                scales: (0...8).map { r0 + (r1 - r0) * Float($0) / 8 })
        }
        let membraneColor: (SIMD3<Float>, Float) -> (MeshVertex) -> RGBAColor = { origin, reach in
            { v in
                let t = min(simd_distance(v.position, origin) / reach, 1)
                return RGBAColor(sRGB: [0.32, 0.04, 0.05]).interpolated(to: RGBAColor(sRGB: [0.85, 0.28, 0.08]), fraction: t)
            }
        }
        // Finger panels fan out from the wrist with a scalloped trailing edge.
        var panels: [MeshData] = []
        for i in 0..<(fingers.count - 1) {
            let a = fingers[i], b = fingers[i + 1]
            panels.append(try MeshBuilder.surface(uSegments: 8, vSegments: 6) { uv in
                let u = 0.06 + uv.x * 0.94, v = side(s, uv.y)
                let edge = simd_mix(a, b, SIMD3(repeating: v))
                let sag = pow(u, 3) * sin(v * .pi) * 0.24
                return wrist + (edge - wrist) * (u - sag)
            }.coloring(membraneColor(wrist, 1.1)))
        }
        let membrane = try merge(panels)
        // The inner panel joins the arm to the dragon's flank.
        let flank = SIMD3<Float>(s * 0.04, -0.2, -0.95)
        let trailEnd = elbow + fingers[3]
        let lead: (Float) -> SIMD3<Float> = { u in
            u < 0.45 ? simd_mix(.zero, elbow, SIMD3(repeating: u / 0.45))
                     : simd_mix(elbow, elbow + wrist, SIMD3(repeating: (u - 0.45) / 0.55))
        }
        let inner = try MeshBuilder.surface(uSegments: 10, vSegments: 5) { uv in
            let u = side(s, uv.x)
            let trail = simd_mix(flank, trailEnd, SIMD3(repeating: u))
            let sagDirection = simd_normalize(lead(u) - trail)
            let point = simd_mix(lead(u), trail, SIMD3(repeating: uv.y))
            return point + sagDirection * (sin(u * .pi) * 0.16 * pow(uv.y, 2))
        }.coloring(membraneColor(.zero, 1.6))
        let arm = try merge([
            bone(.zero, elbow, 0.075, 0.055),
            MeshBuilder.sphere(radius: 0.065, latitudeSegments: 8, longitudeSegments: 10).moved(elbow),
        ])
        var forearm = [
            try bone(.zero, wrist, 0.055, 0.045, lift: 0.03),
            try MeshBuilder.sphere(radius: 0.06, latitudeSegments: 8, longitudeSegments: 10).moved(wrist),
        ]
        for (i, tip) in fingers.enumerated() {
            forearm.append(try bone(wrist, tip, i == 0 ? 0.04 : 0.032, 0.008, lift: i == 0 ? 0.1 : 0.04))
        }
        return Wing(arm: arm, inner: inner, forearm: try merge(forearm), membrane: membrane, elbow: elbow)
    }
    let wingL = try wing(1), wingR = try wing(-1)
    let thumbClaw = try MeshBuilder.cone(radius: 0.025, height: 0.1, segments: 6)

    // MARK: Legs

    func leg(hind: Bool) throws -> (MeshData, MeshData) {
        let r: Float = hind ? 1 : 0.75
        let knee = SIMD3<Float>(0, -0.42 * (hind ? 1 : 1.05), hind ? 0.2 : -0.08)
        let ankle = SIMD3<Float>(0, hind ? -0.72 : -0.8, hind ? -0.12 : 0.06)
        let foot = SIMD3<Float>(0, -0.93, hind ? 0.02 : 0.12)
        let limb = Bezier([0, -0.2, hind ? 0.1 : 0], knee, knee, ankle)
        var parts = [
            try MeshBuilder.sphere(radius: 0.24 * r, latitudeSegments: 12, longitudeSegments: 16)
                .moved([0, -0.12, 0.02], scale: [0.85, 1.35, 1.15]),
            try MeshBuilder.sweep(circle, along: (0...8).map { limb.point(Float($0) / 8) },
                                  scales: (0...8).map { (0.13 - Float($0) / 8 * 0.05) * r }),
            try MeshBuilder.sweep(circle, along: [ankle, (ankle + foot) / 2, foot], scales: [0.075 * r, 0.068 * r, 0.06 * r]),
        ]
        var claws: [MeshData] = []
        for a: Float in [-0.45, 0, 0.45] {
            let toe = foot + [sin(a) * 0.09, -0.005, cos(a) * 0.1]
            parts.append(try MeshBuilder.sphere(radius: 0.05 * r, latitudeSegments: 8, longitudeSegments: 10)
                .moved(toe, rotation: .y(a), scale: [0.75, 0.6, 1.7]))
            claws.append(try MeshBuilder.cone(radius: 0.025 * r, height: 0.1 * r, segments: 6)
                .moved(toe + [sin(a) * 0.08, -0.01, cos(a) * 0.08], rotation: .y(a) * .x(.pi / 2 + 0.35)))
        }
        return (try merge(parts).recalculatingNormals(smoothingAngle: .pi / 3).coloring(scaleColor), try merge(claws))
    }
    let hindLeg = try leg(hind: true), foreLeg = try leg(hind: false)

    // MARK: Assembly

    let shoulderL = SIMD3<Float>(0.3, 1.55, 0.2), shoulderR = SIMD3<Float>(-0.3, 1.55, 0.2)
    var parts: [ModelPartDefinition] = [
        ModelPartDefinition(id: rid("hide"), geometry: skin, material: rid("scale")),
        jointPart("skull", skull, "scale", joint: "head"),
        jointPart("brows", brows, "scale", joint: "head"),
        jointPart("horns", try merge(horns), "horn", joint: "head"),
        jointPart("eyes", eyes, "eye", joint: "head"),
        jointPart("pupils", pupils, "ink", joint: "head"),
        jointPart("nostrils", nostrils, "ember", joint: "head"),
        jointPart("maw", maw, "ember", joint: "head"),
        jointPart("upperTeeth", try merge(upperTeeth), "bone", joint: "head"),
        part("jaw", jaw, "scale", at: hinge, parent: "skull"),
        part("lowerTeeth", try merge(lowerTeeth), "bone", parent: "jaw"),
        jointPart("spade", spade, "horn", joint: "tail4"),
        jointPart("wingL", wingL.arm, "hide", at: local(shoulderL, "chest"), joint: "chest"),
        part("wingInnerL", wingL.inner, "membrane", parent: "wingL"),
        part("forearmL", wingL.forearm, "hide", at: wingL.elbow, parent: "wingL"),
        part("membraneL", wingL.membrane, "membrane", parent: "forearmL"),
        jointPart("wingR", wingR.arm, "hide", at: local(shoulderR, "chest"), joint: "chest"),
        part("wingInnerR", wingR.inner, "membrane", parent: "wingR"),
        part("forearmR", wingR.forearm, "hide", at: wingR.elbow, parent: "wingR"),
        part("membraneR", wingR.membrane, "membrane", parent: "forearmR"),
        part("thumbL", thumbClaw, "bone", at: [0.55, 0.42, -0.3], rotation: .x(0.9), parent: "forearmL"),
        part("thumbR", thumbClaw, "bone", at: [-0.55, 0.42, -0.3], rotation: .x(0.9), parent: "forearmR"),
    ]
    for (name, mesh, claws, joint, anchor) in [
        ("legFL", foreLeg.0, foreLeg.1, "chest", SIMD3<Float>(0.34, 1.0, 0.45)),
        ("legFR", foreLeg.0, foreLeg.1, "chest", SIMD3<Float>(-0.34, 1.0, 0.45)),
        ("legBL", hindLeg.0, hindLeg.1, "hips", SIMD3<Float>(0.4, 0.98, -0.5)),
        ("legBR", hindLeg.0, hindLeg.1, "hips", SIMD3<Float>(-0.4, 0.98, -0.5)),
    ] {
        parts.append(jointPart(name, mesh, "scale", at: anchor - jointPosition[joint]!, joint: joint))
        parts.append(part(name + "Claws", claws, "bone", parent: name))
    }
    for (joint, meshes) in spines.sorted(by: { $0.key < $1.key }) {
        parts.append(jointPart("spines-" + joint, try merge(meshes), "horn", joint: joint))
    }

    var asset = ModelAssetDefinition(
        name: "Varg",
        materials: [
            material("scale", [1, 1, 1], roughness: 0.45, metallic: 0.15, vertexColor: true),
            material("hide", [0.3, 0.06, 0.06], roughness: 0.5, metallic: 0.1),
            material("membrane", [1, 1, 1], roughness: 0.8, vertexColor: true, doubleSided: true),
            material("horn", [1, 1, 1], roughness: 0.35, vertexColor: true),
            material("bone", [0.95, 0.9, 0.78], roughness: 0.4),
            material("eye", [1.0, 0.65, 0.1], glow: 5),
            material("ember", [1.0, 0.42, 0.06], glow: 7),
            material("ink", [0.05, 0.02, 0.02], roughness: 0.2),
        ],
        parts: parts, rig: rig,
        sockets: [SocketDefinition(id: rid("mouth"), parent: .joint(rid("head")), transform: move([0, -0.02, 0.66]))])

    // MARK: Clips

    let rest = asset.restPose
    func j(_ name: String, _ rotation: simd_quatf = .identity, _ offset: SIMD3<Float> = .zero) -> (AnimationTarget, ModelTransform) {
        let base = rest.transforms[.joint(rid(name))]!
        return (.joint(rid(name)), ModelTransform(rotation: base.rotation * rotation, translation: base.translation + offset))
    }
    func p(_ name: String, _ rotation: simd_quatf = .identity, _ offset: SIMD3<Float> = .zero) -> (AnimationTarget, ModelTransform) {
        let base = rest.transforms[.part(rid(name))]!
        return (.part(rid(name)), ModelTransform(scale: base.scale, rotation: base.rotation * rotation, translation: base.translation + offset))
    }
    func clip(_ name: String, _ duration: Float, loop: Bool, _ body: @escaping (Float) -> [(AnimationTarget, ModelTransform)]) throws -> AnimationClipDefinition {
        try AnimationClipDefinition.bake(id: rid(name), duration: duration, sampleRate: 30, reference: rest,
                                         loopMode: loop ? .loop : .once) { t in
            var transforms = rest.transforms
            for (target, transform) in body(t) { transforms[target] = transform }
            return PoseDefinition(id: rid(name), transforms: transforms)
        }
    }
    func tailWave(_ t: Float, _ speed: Float, _ amount: Float) -> [(AnimationTarget, ModelTransform)] {
        (1...4).map { i in j("tail\(i)", .y(sin(t * speed - Float(i) * 0.8) * amount)) }
    }
    func wings(spread: Float, fold: Float) -> [(AnimationTarget, ModelTransform)] {
        [p("wingL", .z(spread)), p("wingR", .z(-spread)), p("forearmL", .z(fold)), p("forearmR", .z(-fold))]
    }

    asset.clips = [
        try clip("idle", 3, loop: true) { t in
            let w = t / 3 * 2 * .pi
            return [
                j("chest", .identity, [0, sin(w) * 0.025, 0]),
                j("neck1", .x(sin(w) * 0.05)),
                j("neck2", .x(-sin(w) * 0.06)),
                j("head", .x(sin(w + 0.6) * 0.06) * .y(sin(w * 0.5) * 0.18)),
                p("jaw", .x(max(sin(w * 2), 0) * 0.08)),
            ] + tailWave(t, 2.1, 0.12) + wings(spread: sin(w * 2) * 0.1, fold: 0.05 + sin(w * 2 + 0.5) * 0.08)
        },
        try clip("attack", 1.0, loop: false) { t in
            let rear = sin(min(t / 0.35, 1) * .pi / 2) * (t < 0.35 ? 1 : max(0, 1 - (t - 0.35) / 0.2))
            let bite = t < 0.35 ? 0 : sin(min((t - 0.35) / 0.65, 1) * .pi)
            return [
                j("neck1", .x(-rear * 0.3 + bite * 0.35)),
                j("neck2", .x(-rear * 0.2 + bite * 0.25)),
                j("head", .x(rear * -0.3 + bite * 0.35)),
                p("jaw", .x(rear * 0.7 + bite * 0.2)),
                p("legFL", .x(-rear * 0.6 - bite * 0.3), [0, rear * 0.15, 0]),
            ] + wings(spread: rear * 0.35, fold: -rear * 0.2) + tailWave(t, 6, 0.2)
        },
        try clip("breath", 2.0, loop: false) { t in
            // Inhale and rear up (0 - 0.6 s), exhale fire downward (0.6 - 1.7 s), recover.
            let inhale = sin(min(t / 0.6, 1) * .pi / 2) * (t < 0.6 ? 1 : max(0, 1 - (t - 0.6) / 0.25))
            let blast = t < 0.6 ? 0 : sin(min((t - 0.6) / 1.4, 1) * .pi)
            let shake = blast * sin(t * 50) * 0.02
            return [
                j("chest", .x(-inhale * 0.08), [0, inhale * 0.05, 0]),
                j("neck1", .x(-inhale * 0.35 + blast * 0.22)),
                j("neck2", .x(-inhale * 0.25 + blast * 0.18 + shake)),
                j("head", .x(-inhale * 0.35 + blast * 0.32) * .y(shake)),
                p("jaw", .x(inhale * 0.1 + blast * 0.75)),
            ] + wings(spread: inhale * 0.5 - blast * 0.1, fold: -inhale * 0.25) + tailWave(t, 4, 0.1 + inhale * 0.15)
        },
        try clip("hurt", 0.6, loop: false) { t in
            let k = sin(min(t / 0.6, 1) * .pi)
            return [
                j("chest", .x(-k * 0.08), [0, 0, -k * 0.12]),
                j("neck1", .x(-k * 0.25)),
                j("head", .x(-k * 0.3) * .z(sin(t * 30) * 0.12 * k)),
                p("jaw", .x(k * 0.45)),
            ] + wings(spread: k * 0.3, fold: -k * 0.3)
        },
    ]
    return try asset.validated()
}

// MARK: - Helpers

private func scaleColor(_ v: MeshVertex) -> RGBAColor {
    // Crimson back, darker flanks, banded golden belly plates.
    let up = v.normal.y
    let belly = simd_clamp(-up * 1.4 - 0.15, 0, 1)
    let band = 0.82 + 0.18 * sin(v.position.z * 26 + v.position.y * 10)
    let back = RGBAColor(sRGB: [0.55, 0.08, 0.06]).interpolated(
        to: RGBAColor(sRGB: [0.2, 0.03, 0.04]), fraction: simd_clamp(0.5 - up * 0.5, 0, 1))
    return back.interpolated(to: RGBAColor(sRGB: [0.92 * band, 0.62 * band, 0.26 * band]), fraction: belly)
}

private func ellipse(_ rx: Float, _ ry: Float, segments: Int = 20) -> [SIMD2<Float>] {
    (0..<segments).map { i in
        let a = Float(i) / Float(segments) * 2 * .pi
        return [cos(a) * rx, sin(a) * ry]
    }
}

private func interpolate(
    _ sections: [(z: Float, rx: Float, ry: Float, cy: Float)], at z: Float
) -> (z: Float, rx: Float, ry: Float, cy: Float) {
    guard let upper = sections.firstIndex(where: { $0.z >= z }), upper > 0 else {
        return z <= sections[0].z ? sections[0] : sections[sections.count - 1]
    }
    let a = sections[upper - 1], b = sections[upper]
    let t = (z - a.z) / (b.z - a.z)
    return (z, a.rx + (b.rx - a.rx) * t, a.ry + (b.ry - a.ry) * t, a.cy + (b.cy - a.cy) * t)
}

/// Mirrors the surface parameter so both wings keep the same winding.
private func side(_ s: Float, _ value: Float) -> Float { s > 0 ? value : 1 - value }

private func jointPart(
    _ name: String, _ mesh: MeshData, _ materialName: String, at translation: SIMD3<Float> = .zero, joint: String
) -> ModelPartDefinition {
    ModelPartDefinition(
        id: rid(name), mesh: mesh, material: rid(materialName), transform: move(translation),
        parent: .joint(rid(joint)))
}

struct Bezier {
    let p0, p1, p2, p3: SIMD3<Float>
    init(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>) {
        (self.p0, self.p1, self.p2, self.p3) = (p0, p1, p2, p3)
    }
    func point(_ t: Float) -> SIMD3<Float> {
        let u = 1 - t
        return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
    }
    func tangent(_ t: Float) -> SIMD3<Float> {
        let u = 1 - t
        return 3 * u * u * (p1 - p0) + 6 * u * t * (p2 - p1) + 3 * t * t * (p3 - p2)
    }
}

#Preview("Varg") { ModelAssetPreview(asset: try! makeDragon()) }
