import Realitizer
import simd

// Small helpers so the model files read like a parts list.

func rid(_ name: String) -> AnyRealitizerID { AnyRealitizerID(name) }

func material(
    _ name: String, _ rgb: SIMD3<Float>, roughness: Float = 0.6, metallic: Float = 0,
    glow: Float = 0, vertexColor: Bool = false, doubleSided: Bool = false
) -> MaterialDefinition {
    var m = MaterialDefinition(
        id: rid(name), baseColor: RGBAColor(sRGB: rgb), roughness: roughness, metallic: metallic,
        vertexColorMode: vertexColor ? .multiply : .ignore)
    if glow > 0 {
        m.emissiveColor = RGBAColor(sRGB: rgb)
        m.emissiveIntensity = glow
    }
    m.doubleSided = doubleSided
    return m
}

func part(
    _ name: String, _ mesh: MeshData, _ materialName: String,
    at translation: SIMD3<Float> = .zero, rotation: simd_quatf = .identity,
    scale: SIMD3<Float> = .one, parent: String? = nil
) -> ModelPartDefinition {
    ModelPartDefinition(
        id: rid(name), mesh: mesh, material: rid(materialName),
        transform: ModelTransform(scale: scale, rotation: rotation, translation: translation),
        parent: parent.map { .part(rid($0)) })
}

func move(_ t: SIMD3<Float>, rotation: simd_quatf = .identity, scale: SIMD3<Float> = .one) -> ModelTransform {
    ModelTransform(scale: scale, rotation: rotation, translation: t)
}

extension simd_quatf {
    static let identity = simd_quatf(angle: 0, axis: [0, 1, 0])
    static func x(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [1, 0, 0]) }
    static func y(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [0, 1, 0]) }
    static func z(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [0, 0, 1]) }
}

extension MeshData {
    func moved(_ t: SIMD3<Float>, rotation: simd_quatf = .identity, scale: SIMD3<Float> = .one) -> MeshData {
        transformed(by: move(t, rotation: rotation, scale: scale))
    }
}

/// Merges several already-placed meshes into one.
func merge(_ meshes: [MeshData]) throws -> MeshData {
    var builder = MeshBuilder()
    for mesh in meshes { builder.append(mesh) }
    return try builder.build()
}

/// A pose that starts from `rest` and overrides the given parts.
func pose(_ name: String, rest: PoseDefinition, _ overrides: [String: ModelTransform]) -> PoseDefinition {
    var transforms = rest.transforms
    for (key, value) in overrides { transforms[.part(rid(key))] = value }
    return PoseDefinition(id: rid(name), transforms: transforms)
}

/// Returns the rest transform of `name` with extra rotation/offset applied on top.
func offset(
    _ name: String, in asset: ModelAssetDefinition, rotation: simd_quatf = .identity,
    translation: SIMD3<Float> = .zero, scale: SIMD3<Float> = .one
) -> ModelTransform {
    let rest = asset.parts.first { $0.id == rid(name) }!.transform
    return ModelTransform(
        scale: rest.scale * scale, rotation: rest.rotation * rotation,
        translation: rest.translation + translation)
}

/// Bakes a clip by evaluating per-part transforms at each sample time.
func bakeClip(
    _ name: String, asset: ModelAssetDefinition, duration: Float, loop: Bool,
    _ body: @escaping (Float) -> [String: ModelTransform]
) throws -> AnimationClipDefinition {
    let rest = asset.restPose
    return try AnimationClipDefinition.bake(
        id: rid(name), duration: duration, sampleRate: 30, reference: rest,
        loopMode: loop ? .loop : .once
    ) { t in pose(name, rest: rest, body(t)) }
}

/// Deterministic pseudo random in 0..<1 for scattering details.
func hash01(_ x: Int, _ y: Int, _ salt: Int = 0) -> Float {
    var h = UInt64(bitPattern: Int64(x &* 73856093 ^ y &* 19349663 ^ salt &* 83492791))
    h ^= h >> 33
    h &*= 0xff51afd7ed558ccd
    h ^= h >> 33
    return Float(h % 10_000) / 10_000
}
