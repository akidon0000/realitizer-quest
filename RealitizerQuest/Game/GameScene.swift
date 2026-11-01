import Realitizer
import RealitizerRealityKit
import RealityKit
import UIKit
import simd

/// Owns every RealityKit entity. Assets are generated and compiled once in `load()`;
/// gameplay only switches visibility, places roots and samples clips.
@MainActor
final class GameScene {
    let root = Entity()
    private let camera = PerspectiveCamera()
    private let fieldRoot = Entity()
    private let battleRoot = Entity()

    private var fieldHero: Actor!
    private var showcaseHero: Actor!
    private var monsters: [MonsterKind: Actor] = [:]
    private var stages: [StageTheme: Entity] = [:]
    private var effects: RuntimeModelInstance!
    private var activeMonster: Actor?
    private var activeStage: StageTheme?

    private var cameraTarget: SIMD3<Float> = .zero
    private var cameraEye: SIMD3<Float> = [0, 5, 5]
    private var cameraMode: CameraMode = .orbit(center: [0, 1.2, 0], radius: 6.5, height: 2.2)
    private var time: Float = 0
    private var tweens: [Tween] = []

    private let fireBreath = Entity()
    private let embers = Entity()
    private let mouthLight = PointLight()

    enum CameraMode {
        case follow
        case fixed(eye: SIMD3<Float>, target: SIMD3<Float>)
        case orbit(center: SIMD3<Float>, radius: Float, height: Float)
        /// Driven by the bestiary's drag and pinch gestures.
        case inspect(center: SIMD3<Float>)
    }

    /// Bestiary camera angles, written by the gestures.
    var inspectYaw: Float = 0.6
    var inspectPitch: Float = 0.25
    var inspectDistance: Float = 3

    private(set) var isLoaded = false

    /// Compiles generated definitions into RealityKit resources. Runs once.
    func load(_ assets: GameAssets) throws {
        let resources = try ModelRenderingResources.shared()
        func compile(_ definition: ModelAssetDefinition) throws -> CompiledModelAsset {
            do {
                return try RealityKitModelCompiler.compile(definition, resources: resources)
            } catch {
                throw AssetLoadError(asset: definition.name, underlying: error)
            }
        }

        let hero = try compile(assets.hero)
        fieldHero = try Actor(hero.instantiate(), idle: "idle")
        showcaseHero = try Actor(hero.instantiate(), idle: "idle")

        let field = try compile(assets.field).instantiate()
        fieldRoot.addChild(field.root)
        fieldRoot.addChild(fieldHero.instance.root)

        for (kind, definition) in assets.monsters {
            let actor = try Actor(compile(definition).instantiate(), idle: "idle")
            actor.instance.root.isEnabled = false
            battleRoot.addChild(actor.instance.root)
            monsters[kind] = actor
        }
        for (theme, definition) in assets.stages {
            let stage = try compile(definition).instantiate().root
            stage.isEnabled = false
            battleRoot.addChild(stage)
            stages[theme] = stage
        }
        showcaseHero.instance.root.isEnabled = false
        battleRoot.addChild(showcaseHero.instance.root)

        effects = try compile(assets.effects).instantiate()
        for name in ["slash", "fire", "heal"] {
            try effects.part(rid(name)).isEnabled = false
        }
        battleRoot.addChild(effects.root)

        // Fire hangs from the skull part so it follows the head exactly; the tip of the snout is at z = 0.66.
        let skull = try monsters[.varg]!.instance.part(rid("skull"))
        let mouth = Entity()
        mouth.position = [0, -0.02, 0.66]
        skull.addChild(mouth)
        fireBreath.components.set(Self.flameEmitter())
        embers.components.set(Self.emberEmitter())
        mouthLight.light.color = .init(red: 1, green: 0.5, blue: 0.15, alpha: 1)
        mouthLight.light.intensity = 0
        mouthLight.light.attenuationRadius = 7
        mouthLight.position = [0, 0, 0.6]
        // Particles leave along the emitter entity's +y, so turn +y toward the snout (+z).
        fireBreath.orientation = simd_quatf(from: [0, 1, 0], to: [0, 0, 1])
        embers.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize([0, 0.6, 1]))
        mouth.addChild(fireBreath)
        mouth.addChild(embers)
        mouth.addChild(mouthLight)

        root.addChild(fieldRoot)
        root.addChild(battleRoot)
        root.addChild(camera)
        camera.camera.fieldOfViewInDegrees = 50

        let sun = DirectionalLight()
        sun.light.intensity = 4200
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 18, depthBias: 1)
        sun.look(at: .zero, from: [-4, 8, 6], relativeTo: nil)
        root.addChild(sun)
        let fill = DirectionalLight()
        fill.light.intensity = 1600
        fill.light.color = .init(red: 0.75, green: 0.82, blue: 1, alpha: 1)
        fill.look(at: .zero, from: [5, 3, -4], relativeTo: nil)
        root.addChild(fill)
        let front = DirectionalLight()
        front.light.intensity = 1300
        front.look(at: .zero, from: [0, 2, 8], relativeTo: nil)
        root.addChild(front)
        isLoaded = true
    }

    // MARK: - Modes

    func showTitle() {
        showBattleStage(.lair)
        show(monster: .varg)
        showcaseHero.instance.root.isEnabled = false
        cameraMode = .orbit(center: [0, 1.2, 0], radius: 6.5, height: 1.8)
    }

    func showField(hero position: SIMD3<Float>, yaw: Float) {
        fieldRoot.isEnabled = true
        battleRoot.isEnabled = false
        placeHero(position, yaw: yaw, walking: false)
        cameraTarget = position
        cameraEye = position + followOffset
        cameraMode = .follow
    }

    func showBattle(_ kind: MonsterKind, theme: StageTheme) {
        showBattleStage(theme)
        showcaseHero.instance.root.isEnabled = false
        show(monster: kind)
        cameraMode = kind.isBoss
            ? .fixed(eye: [0, 2.1, 7.6], target: [0, 0.95, 0])
            : .fixed(eye: [0, 0.8, 2.7], target: [0, 0.42, 0])
    }

    func showEnding() {
        showBattleStage(.plains)
        activeMonster?.instance.root.isEnabled = false
        activeMonster = nil
        showcaseHero.instance.root.isEnabled = true
        showcaseHero.instance.root.transform = Transform(scale: .one * 1.4)
        cameraMode = .orbit(center: [0, 0.75, 0], radius: 3.2, height: 0.6)
    }

    func showBestiary(_ kind: MonsterKind) {
        showBattleStage(kind.isBoss ? .lair : [.kokegame, .yoroigani].contains(kind) ? .forest : .plains)
        showcaseHero.instance.root.isEnabled = false
        show(monster: kind)
        inspectYaw = 0.6
        inspectPitch = kind.isBoss ? 0.15 : 0.22
        inspectDistance = kind.isBoss ? 9.5 : kind == .kokegame ? 3.3 : 2.6
        // Aim below the model's middle so it sits above the entry card.
        cameraMode = .inspect(center: kind.isBoss ? [0, 0.75, -0.3] : [0, 0.18, 0])
    }

    enum Display: CaseIterable { case shaded, wireframe, parts }

    /// Swaps every material of the shown monster for a diagnostic one.
    func setDisplay(_ display: Display) {
        guard let instance = activeMonster?.instance else { return }
        var overrides: [AnyRealitizerID: any Material] = [:]
        switch display {
        case .shaded:
            break
        case .wireframe:
            var lines = UnlitMaterial(color: .init(red: 0.45, green: 0.95, blue: 1, alpha: 1))
            lines.triangleFillMode = .lines
            for definition in instance.definition.materials { overrides[definition.id] = lines }
        case .parts:
            for (index, definition) in instance.definition.materials.enumerated() {
                let hue = CGFloat(index) / CGFloat(max(instance.definition.materials.count, 1))
                overrides[definition.id] = SimpleMaterial(
                    color: .init(hue: hue, saturation: 0.65, brightness: 0.95, alpha: 1), roughness: 0.6, isMetallic: false)
            }
        }
        try? instance.setVisualizationMaterials(overrides)
    }

    func statistics(of kind: MonsterKind) -> ModelStatistics? { monsters[kind]?.instance.statistics }

    private func showBattleStage(_ theme: StageTheme) {
        fieldRoot.isEnabled = false
        battleRoot.isEnabled = true
        for (key, stage) in stages { stage.isEnabled = key == theme }
        activeStage = theme
    }

    private func show(monster kind: MonsterKind) {
        for actor in monsters.values {
            actor.instance.root.isEnabled = false
            try? actor.instance.setVisualizationMaterials([:])
        }
        let actor = monsters[kind]!
        actor.instance.root.isEnabled = true
        actor.instance.root.transform = Transform()
        actor.play("idle")
        activeMonster = actor
    }

    // MARK: - Field hero

    private let followOffset: SIMD3<Float> = [0, 6.0, 3.9]

    func placeHero(_ position: SIMD3<Float>, yaw: Float, walking: Bool) {
        let root = fieldHero.instance.root
        root.position = position
        let current = root.orientation
        let target = simd_quatf(angle: yaw, axis: [0, 1, 0])
        root.orientation = simd_slerp(current, target, 0.35)
        if walking, fieldHero.clip != "walk" { fieldHero.play("walk") }
        if !walking, fieldHero.clip != "idle" { fieldHero.play("idle") }
        cameraTarget = position
    }

    // MARK: - Battle effects

    func playMonster(_ clip: String) { activeMonster?.play(clip, then: "idle") }

    func blinkMonster() {
        guard let entity = activeMonster?.instance.root else { return }
        tween(0.45) { t in
            entity.isEnabled = t >= 1 || Int(t * 9) % 2 == 0
        }
    }

    func defeatMonster() {
        guard let actor = activeMonster else { return }
        let entity = actor.instance.root
        let boss = actor === monsters[.varg]
        tween(boss ? 2.0 : 0.6) { t in
            let s = max(1 - t, 0.001)
            entity.transform = Transform(
                scale: [1 + t * 0.3, s, 1 + t * 0.3],
                rotation: simd_quatf(angle: t * (boss ? 1.5 : 4), axis: [0, 1, 0]))
            if t >= 1 { entity.isEnabled = false }
        }
    }

    func playSlash() {
        guard let slash = try? effects.part(rid("slash")) else { return }
        let height: Float = activeMonster === monsters[.varg] ? 1.4 : 0.45
        let z: Float = activeMonster === monsters[.varg] ? 1.4 : 0.45
        tween(0.28) { t in
            slash.isEnabled = t < 1
            let angle: Float = -0.7
            let travel = (t - 0.5) * 0.9
            slash.transform = Transform(
                scale: [max(sin(t * .pi), 0.01) * 1.2, 1, 1],
                rotation: simd_quatf(angle: angle, axis: [0, 0, 1]),
                translation: [travel * cos(angle), height + travel * sin(angle), z])
        }
    }

    func playFire() {
        guard let fire = try? effects.part(rid("fire")) else { return }
        let boss = activeMonster === monsters[.varg]
        let target: SIMD3<Float> = boss ? [0, 1.5, 0.9] : [0, 0.45, 0.2]
        let start: SIMD3<Float> = boss ? [0, 1.0, 5.2] : [0, 0.3, 2.2]
        tween(0.6) { t in
            fire.isEnabled = t < 1
            let p = simd_mix(start, target, SIMD3(repeating: min(t * 1.4, 1)))
            let burst: Float = t > 0.7 ? 1 + (t - 0.7) * 6 : 1
            fire.transform = Transform(
                scale: .one * (boss ? 1.6 : 0.8) * burst,
                rotation: simd_quatf(angle: t * 12, axis: [0, 1, 0]), translation: p)
        }
    }

    func playHeal() {
        guard let ring = try? effects.part(rid("heal")) else { return }
        let showcase = activeMonster == nil
        let eye = currentEye
        let ahead = simd_normalize(cameraTargetPoint - eye)
        tween(0.8) { t in
            ring.isEnabled = t < 1
            // a rising ring just in front of the first-person camera
            let base = showcase ? SIMD3<Float>(0, 0, 0) : eye + ahead * 1.2 - [0, 0.6, 0]
            ring.transform = Transform(
                scale: [1 + t * 0.6, 1, 1 + t * 0.6],
                rotation: simd_quatf(angle: t * 4, axis: [0, 1, 0]),
                translation: base + [0, t * 0.8, 0])
        }
    }

    /// Plays the dragon's "breath" clip and pours flame particles from its mouth while the jaw is open.
    func playBreath() {
        monsters[.varg]?.play("breath", then: "idle")
        let flame = fireBreath, light = mouthLight
        tween(1.75) { t in
            let blowing = t > 0.45 && t < 0.9  // after the head has swung down
            if var emitter = flame.components[ParticleEmitterComponent.self], emitter.isEmitting != blowing {
                emitter.isEmitting = blowing
                flame.components.set(emitter)
            }
            let flicker = Float.random(in: 0.75...1.0)
            light.light.intensity = blowing ? 60_000 * flicker : (t < 0.45 ? 6_000 * t / 0.45 : 0)
        }
    }

    private static func flameEmitter() -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .sphere
        emitter.emitterShapeSize = [0.06, 0.06, 0.06]
        emitter.birthDirection = .local
        emitter.emissionDirection = [0, 1, 0]
        emitter.speed = 4.2
        emitter.speedVariation = 1
        emitter.fieldSimulationSpace = .global
        emitter.isEmitting = false
        emitter.mainEmitter.birthRate = 900
        emitter.mainEmitter.lifeSpan = 0.65
        emitter.mainEmitter.lifeSpanVariation = 0.2
        emitter.mainEmitter.spreadingAngle = 0.16
        emitter.mainEmitter.size = 0.13
        emitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 4.5
        emitter.mainEmitter.dampingFactor = 0
        emitter.mainEmitter.acceleration = .zero
        emitter.mainEmitter.noiseStrength = 0.1
        emitter.mainEmitter.opacityCurve = .linearFadeOut
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.color = .evolving(
            start: .single(.init(red: 1, green: 0.72, blue: 0.25, alpha: 1)),
            end: .single(.init(red: 0.7, green: 0.08, blue: 0.02, alpha: 1)))
        return emitter
    }

    /// A few sparks that keep drifting out of the mouth, so the dragon smoulders even when idle.
    private static func emberEmitter() -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .sphere
        emitter.emitterShapeSize = [0.05, 0.03, 0.05]
        emitter.birthDirection = .local
        emitter.emissionDirection = [0, 1, 0]
        emitter.speed = 0.35
        emitter.fieldSimulationSpace = .global
        emitter.mainEmitter.birthRate = 28
        emitter.mainEmitter.lifeSpan = 1.4
        emitter.mainEmitter.spreadingAngle = 0.6
        emitter.mainEmitter.size = 0.018
        emitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.2
        emitter.mainEmitter.acceleration = [0, 0.5, 0]
        emitter.mainEmitter.noiseStrength = 0.2
        emitter.mainEmitter.opacityCurve = .linearFadeOut
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.color = .evolving(
            start: .single(.init(red: 1, green: 0.75, blue: 0.3, alpha: 1)),
            end: .single(.init(red: 0.9, green: 0.2, blue: 0.05, alpha: 1)))
        return emitter
    }

    private func tween(_ duration: Float, _ step: @escaping (Float) -> Void) {
        step(0)
        tweens.append(Tween(duration: duration, step: step))
    }

    // MARK: - Frame update

    private var currentEye: SIMD3<Float> = [0, 5, 5]
    private var cameraTargetPoint: SIMD3<Float> = .zero

    func update(_ dt: Float) {
        guard isLoaded else { return }
        time += dt
        fieldHero.advance(dt)
        showcaseHero.advance(dt)
        activeMonster?.advance(dt)

        tweens = tweens.filter { tween in
            tween.elapsed += dt
            let t = min(tween.elapsed / tween.duration, 1)
            tween.step(t)
            return t < 1
        }

        var eye: SIMD3<Float>
        var target: SIMD3<Float>
        switch cameraMode {
        case .follow:
            target = cameraTarget + [0, 0.3, -0.4]
            let desired = cameraTarget + followOffset
            cameraEye = simd_mix(cameraEye, desired, SIMD3(repeating: min(dt * 6, 1)))
            eye = cameraEye
        case .fixed(let e, let t):
            eye = e
            target = t
        case .orbit(let center, let radius, let height):
            let a = time * 0.25
            eye = center + [sin(a) * radius, height, cos(a) * radius]
            target = center
        case .inspect(let center):
            let flat = cos(inspectPitch) * inspectDistance
            eye = center + [sin(inspectYaw) * flat, sin(inspectPitch) * inspectDistance, cos(inspectYaw) * flat]
            target = center
        }
        currentEye = eye
        cameraTargetPoint = target
        camera.look(at: target, from: eye, relativeTo: nil)
    }
}

/// A runtime instance plus the clip it is currently sampling.
@MainActor
final class Actor {
    let instance: RuntimeModelInstance
    private(set) var clip: String
    private var clipTime: Float = 0
    private var next: String?
    private let durations: [String: (Float, Bool)]

    init(_ instance: RuntimeModelInstance, idle: String) {
        self.instance = instance
        clip = idle
        var durations: [String: (Float, Bool)] = [:]
        for clip in instance.definition.clips {
            durations[clip.id.rawValue] = (clip.duration, clip.loopMode == .loop)
        }
        self.durations = durations
    }

    func play(_ name: String, then next: String? = nil) {
        clip = name
        clipTime = 0
        self.next = next
    }

    func advance(_ dt: Float) {
        guard instance.root.isEnabled || clip != "idle", let (duration, loops) = durations[clip] else { return }
        clipTime += dt
        if clipTime >= duration {
            if loops {
                clipTime = clipTime.truncatingRemainder(dividingBy: duration)
            } else if let next {
                play(next)
            } else {
                clipTime = duration
            }
        }
        try? instance.sample(rid(clip), at: clipTime)
    }
}

@MainActor
private final class Tween {
    var elapsed: Float = 0
    let duration: Float
    let step: (Float) -> Void

    init(duration: Float, step: @escaping (Float) -> Void) {
        self.duration = duration
        self.step = step
    }
}

/// Every model definition the game uses. Generated off the main actor; only compilation needs it.
struct GameAssets: Sendable {
    var hero: ModelAssetDefinition
    var field: ModelAssetDefinition
    var monsters: [MonsterKind: ModelAssetDefinition]
    var stages: [StageTheme: ModelAssetDefinition]
    var effects: ModelAssetDefinition

    static func generate() throws -> GameAssets {
        func named(_ name: String, _ build: () throws -> ModelAssetDefinition) throws -> ModelAssetDefinition {
            do { return try build() } catch { throw AssetLoadError(asset: name, underlying: error) }
        }
        return GameAssets(
            hero: try named("hero", makeHero),
            field: try named("field", makeField),
            monsters: [
                .mokorin: try named("mokorin", makeMokorin),
                .kinokoro: try named("kinokoro", makeKinokoro),
                .kokegame: try named("kokegame", makeKokegame),
                .yoroigani: try named("yoroigani", makeYoroigani),
                .varg: try named("varg", makeDragon),
            ],
            stages: [
                .plains: try named("plains", { try makeBattleStage(.plains) }),
                .forest: try named("forest", { try makeBattleStage(.forest) }),
                .lair: try named("lair", { try makeBattleStage(.lair) }),
            ],
            effects: try named("effects", makeEffects))
    }
}

struct AssetLoadError: Error, CustomStringConvertible {
    let asset: String
    let underlying: any Error
    var description: String { "\(asset): \(underlying)" }
}
