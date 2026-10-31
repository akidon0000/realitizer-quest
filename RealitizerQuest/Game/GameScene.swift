import Realitizer
import RealitizerRealityKit
import RealityKit
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

    enum CameraMode {
        case follow
        case fixed(eye: SIMD3<Float>, target: SIMD3<Float>)
        case orbit(center: SIMD3<Float>, radius: Float, height: Float)
    }

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
        for name in ["slash", "fire", "heal", "breath"] {
            try effects.part(rid(name)).isEnabled = false
        }
        battleRoot.addChild(effects.root)

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

    private func showBattleStage(_ theme: StageTheme) {
        fieldRoot.isEnabled = false
        battleRoot.isEnabled = true
        for (key, stage) in stages { stage.isEnabled = key == theme }
        activeStage = theme
    }

    private func show(monster kind: MonsterKind) {
        for actor in monsters.values { actor.instance.root.isEnabled = false }
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

    func playBreath() {
        guard let breath = try? effects.part(rid("breath")),
              let head = try? monsters[.varg]?.instance.part(rid("head")) else { return }
        tween(0.9) { t in
            breath.isEnabled = t < 1
            let origin = head.position(relativeTo: self.battleRoot) + [0, -0.1, 0.5]
            let grow = min(t * 3, 1)
            breath.transform = Transform(
                scale: [grow, grow, grow * 1.6],
                rotation: simd_quatf(angle: t * 6, axis: [0, 0, 1]) * simd_quatf(angle: -0.18, axis: [1, 0, 0]),
                translation: origin)
        }
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
