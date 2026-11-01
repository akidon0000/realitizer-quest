import Foundation
import Observation
import simd

enum MonsterKind: CaseIterable, Sendable {
    case mokorin, kinokoro, kokegame, yoroigani, varg

    var name: String {
        switch self {
        case .mokorin: "モコリン"
        case .kinokoro: "キノコロ"
        case .kokegame: "コケガメ"
        case .yoroigani: "ヨロイガニ"
        case .varg: "炎竜ヴァルグ"
        }
    }
    var maxHP: Int { switch self { case .mokorin: 8; case .kinokoro: 15; case .kokegame: 22; case .yoroigani: 30; case .varg: 170 } }
    var attack: Int { switch self { case .mokorin: 6; case .kinokoro: 8; case .kokegame: 10; case .yoroigani: 15; case .varg: 27 } }
    var defense: Int { switch self { case .mokorin: 2; case .kinokoro: 5; case .kokegame: 10; case .yoroigani: 12; case .varg: 18 } }
    var exp: Int { switch self { case .mokorin: 3; case .kinokoro: 6; case .kokegame: 9; case .yoroigani: 13; case .varg: 0 } }
    var isBoss: Bool { self == .varg }
}

struct HeroStats {
    static let expTable = [0, 8, 20, 40, 70, 110, 160, 220, 300, 400, 520]

    var level = 1
    var maxHP = 30
    var hp = 30
    var maxMP = 10
    var mp = 10
    var attack = 8
    var defense = 4
    var exp = 0

    var expToNext: Int? {
        level < Self.expTable.count ? max(Self.expTable[level] - exp, 0) : nil
    }

    mutating func restore() {
        hp = maxHP
        mp = maxMP
    }
}

enum Direction: Sendable {
    case north, south, east, west

    var step: SIMD2<Int> {
        switch self {
        case .north: [0, -1]
        case .south: [0, 1]
        case .east: [1, 0]
        case .west: [-1, 0]
        }
    }
    /// Yaw that turns a +z-facing model toward this direction.
    var yaw: Float {
        switch self {
        case .south: 0
        case .east: .pi / 2
        case .north: .pi
        case .west: -.pi / 2
        }
    }
}

enum Spell: CaseIterable {
    case heal, fire
    var name: String { self == .heal ? "ヒール" : "ファイア" }
    var cost: Int { self == .heal ? 3 : 4 }
}

@MainActor
@Observable
final class Game {
    enum Mode { case loading, title, field, battle, ending, bestiary }
    enum Phase { case idle, command, spells, busy }

    var mode: Mode = .loading
    var phase: Phase = .idle
    var hero = HeroStats()
    var messages: [String] = []
    var enemy: MonsterKind?
    var enemyHP = 0
    var shakeCount = 0
    var flashCount = 0
    var loadError: String?

    var heldDirection: Direction?

    @ObservationIgnored let scene = GameScene()
    @ObservationIgnored private var position = WorldMap.start
    @ObservationIgnored private var facing = Direction.north
    @ObservationIgnored private var moveFrom: SIMD3<Float> = .zero
    @ObservationIgnored private var moveProgress: Float?
    @ObservationIgnored private var stepsSinceBattle = 0
    @ObservationIgnored private var defending = false
    @ObservationIgnored private var bossTurn = 0
    @ObservationIgnored private var lastTile: Tile = .grass

    private let stepDuration: Float = 0.24

    func load() async {
        guard mode == .loading, !scene.isLoaded else { return }
        do {
            let assets = try await Task.detached(priority: .userInitiated) { try GameAssets.generate() }.value
            try scene.load(assets)
            scene.showTitle()
            mode = .title
            // Development shortcut: launch with `-debugBattle <mokorin|kinokoro|kokegame|yoroigani|varg>`.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-bestiary"), i + 1 < args.count, let index = Int(args[i + 1]) {
                bestiaryIndex = index
                openBestiary()
            }
            if let i = args.firstIndex(of: "-debugBattle"), i + 1 < args.count,
               let kind = MonsterKind.allCases.first(where: { "\($0)" == args[i + 1] }) {
                startAdventure()
                if kind.isBoss { hero.level = 8; hero.maxHP = 95; hero.maxMP = 38; hero.attack = 36; hero.defense = 25; hero.restore() }
                await startBattle(kind)
                if kind.isBoss { enemyHP = kind.maxHP / 5 }  // reach the ending quickly
            }
        } catch {
            loadError = "\(error)"
        }
    }

    // MARK: - Title / ending

    func startAdventure() {
        hero = HeroStats()
        position = WorldMap.start
        facing = .north
        mode = .field
        phase = .idle
        scene.showField(hero: WorldMap.world(position), yaw: facing.yaw)
        messages = [
            "王さま「よくぞ来た、ゆうしゃよ。」",
            "「北東の山に 炎竜ヴァルグが すみついた。」",
            "「町で休み、力をつけてから むかうのじゃ。」",
        ]
    }

    // MARK: - Bestiary

    var bestiaryIndex = 0
    var bestiaryDisplay: GameScene.Display = .shaded

    func openBestiary() {
        mode = .bestiary
        showBestiaryEntry(bestiaryIndex)
    }

    func showBestiaryEntry(_ index: Int) {
        let all = MonsterKind.allCases
        bestiaryIndex = (index + all.count) % all.count
        scene.showBestiary(all[bestiaryIndex])
        scene.setDisplay(bestiaryDisplay)
    }

    func setBestiaryDisplay(_ display: GameScene.Display) {
        bestiaryDisplay = display
        scene.setDisplay(display)
    }

    func playBestiaryClip(_ clip: String) {
        if clip == "breath" { scene.playBreath() } else { scene.playMonster(clip) }
    }

    func backToTitle() {
        mode = .title
        messages = []
        scene.showTitle()
    }

    // MARK: - Field

    func tick(_ dt: Float) {
        scene.update(dt)
        guard mode == .field, phase == .idle else { return }
        if let progress = moveProgress {
            let p = min(progress + dt / stepDuration, 1)
            let to = WorldMap.world(position)
            scene.placeHero(simd_mix(moveFrom, to, SIMD3(repeating: p)), yaw: facing.yaw, walking: true)
            if p >= 1 {
                moveProgress = nil
                arrived()
            } else {
                moveProgress = p
            }
        } else if let direction = heldDirection {
            tryMove(direction)
        } else {
            scene.placeHero(WorldMap.world(position), yaw: facing.yaw, walking: false)
        }
    }

    private func tryMove(_ direction: Direction) {
        facing = direction
        let target = position &+ direction.step
        guard WorldMap.tile(target).isWalkable else {
            scene.placeHero(WorldMap.world(position), yaw: facing.yaw, walking: false)
            return
        }
        if !messages.isEmpty { messages = [] }
        moveFrom = WorldMap.world(position)
        position = target
        moveProgress = 0
    }

    private func arrived() {
        let tile = WorldMap.tile(position)
        defer { lastTile = tile }
        stepsSinceBattle += 1
        switch tile {
        case .town where lastTile != .town:
            hero.restore()
            messages = ["宿屋「ようこそ、旅の人。」", "ぐっすり休んだ。HPとMPが 全回復した！"]
        case .castle where lastTile != .castle:
            hero.restore()
            if let next = hero.expToNext {
                messages = ["王さま「つぎのレベルまで あと \(next) の経験値じゃ。」", "HPとMPが 全回復した！"]
            } else {
                messages = ["王さま「もはや そなたに 教えることはない。」"]
            }
        case .lair:
            Task { await startBattle(.varg) }
        case .grass, .forest:
            let rate: Float = tile == .forest ? 0.16 : 0.09
            if stepsSinceBattle >= 4, Float.random(in: 0..<1) < rate {
                Task { await startBattle(randomEncounter(on: tile)) }
            }
        default:
            break
        }
    }

    private func randomEncounter(on tile: Tile) -> MonsterKind {
        let east = position.x >= 10
        let table: [MonsterKind] = switch (east, tile == .forest) {
        case (false, false): [.mokorin, .mokorin, .kinokoro]
        case (false, true): [.mokorin, .kinokoro, .kokegame]
        case (true, false): [.kinokoro, .kinokoro, .yoroigani]
        case (true, true): [.kokegame, .yoroigani, .yoroigani]
        }
        return table.randomElement()!
    }

    // MARK: - Battle

    private func startBattle(_ kind: MonsterKind) async {
        phase = .busy
        heldDirection = nil
        stepsSinceBattle = 0
        bossTurn = 0
        flashCount += 1
        await wait(0.35)
        enemy = kind
        enemyHP = kind.maxHP
        mode = .battle
        let theme: StageTheme = kind.isBoss ? .lair : (WorldMap.tile(position) == .forest ? .forest : .plains)
        scene.showBattle(kind, theme: theme)
        if kind.isBoss {
            messages = ["大地が ふるえる……！", "\(kind.name)が すがたを あらわした！"]
            await wait(1.4)
        } else {
            messages = ["\(kind.name)が とびだしてきた！"]
            await wait(0.8)
        }
        phase = .command
    }

    func choose(_ command: BattleCommand) {
        guard phase == .command || phase == .spells else { return }
        switch command {
        case .spells:
            phase = .spells
        case .back:
            phase = .command
        default:
            phase = .busy
            Task { await runTurn(command) }
        }
    }

    private func runTurn(_ command: BattleCommand) async {
        guard let kind = enemy else { return }
        defending = false
        switch command {
        case .attack:
            messages = ["ゆうしゃの こうげき！"]
            scene.playSlash()
            await wait(0.3)
            let critical = Int.random(in: 0..<16) == 0
            let damage = critical
                ? Int(Float(hero.attack) * Float.random(in: 1.4...1.6))
                : roll(hero.attack, against: kind.defense)
            hitEnemy(damage)
            if critical { messages.append("クリティカルヒット！") }
            messages.append("\(kind.name)に \(damage)の ダメージ！")
        case .cast(.fire):
            hero.mp -= Spell.fire.cost
            messages = ["ゆうしゃは ファイアを となえた！"]
            scene.playFire()
            await wait(0.6)
            let damage = 10 + hero.level * 3 + Int.random(in: -3...3)
            hitEnemy(damage)
            messages.append("\(kind.name)に \(damage)の ダメージ！")
        case .cast(.heal):
            hero.mp -= Spell.heal.cost
            messages = ["ゆうしゃは ヒールを となえた！"]
            scene.playHeal()
            await wait(0.5)
            let amount = min(26 + hero.level * 4 + Int.random(in: 0...6), hero.maxHP - hero.hp)
            hero.hp += amount
            messages.append("HPが \(amount) かいふくした！")
        case .defend:
            defending = true
            messages = ["ゆうしゃは 身をまもっている。"]
        case .run:
            messages = ["ゆうしゃは にげだした！"]
            await wait(0.6)
            if !kind.isBoss, Float.random(in: 0..<1) < 0.7 {
                endBattle()
                return
            }
            messages.append(kind.isBoss ? "しかし 竜の気配が 足をすくませる！" : "しかし にげきれなかった！")
        case .spells, .back:
            break
        }
        await wait(0.9)

        if enemyHP <= 0 {
            await victory(kind)
            return
        }
        await enemyTurn(kind)
        if hero.hp <= 0 {
            await defeat()
            return
        }
        phase = .command
    }

    private func enemyTurn(_ kind: MonsterKind) async {
        bossTurn += 1
        let breath = kind.isBoss && (bossTurn % 3 == 0 || Float.random(in: 0..<1) < 0.2)
        var damage: Int
        if breath {
            messages = ["\(kind.name)は 大きく 息を すいこんだ……！"]
            scene.playBreath()
            await wait(0.65)
            messages.append("灼熱の ほのおが ゆうしゃを つつむ！")
            flashCount += 1
            await wait(0.6)
            damage = Int.random(in: 26...36)
        } else {
            messages = ["\(kind.name)の こうげき！"]
            scene.playMonster("attack")
            await wait(0.4)
            damage = roll(kind.attack, against: hero.defense)
        }
        if defending { damage = max(damage / 2, 1) }
        hero.hp = max(hero.hp - damage, 0)
        shakeCount += 1
        messages.append("ゆうしゃは \(damage)の ダメージを うけた！")
        await wait(0.9)
    }

    private func hitEnemy(_ damage: Int) {
        enemyHP -= damage
        scene.playMonster("hurt")
        scene.blinkMonster()
    }

    private func victory(_ kind: MonsterKind) async {
        scene.defeatMonster()
        if kind.isBoss {
            messages = ["\(kind.name)を たおした！", "国に 平和が もどった……。"]
            await wait(2.4)
            mode = .ending
            phase = .idle
            messages = []
            scene.showEnding()
            return
        }
        messages = ["\(kind.name)を たおした！", "\(kind.exp)ポイントの 経験値を かくとく。"]
        hero.exp += kind.exp
        await wait(1.1)
        while let next = hero.expToNext, next == 0 {
            hero.level += 1
            let hp = Int.random(in: 7...10), mp = Int.random(in: 3...5)
            let atk = Int.random(in: 3...5), def = Int.random(in: 2...4)
            hero.maxHP += hp
            hero.hp += hp
            hero.maxMP += mp
            hero.mp += mp
            hero.attack += atk
            hero.defense += def
            scene.playHeal()
            messages = ["ゆうしゃは レベル\(hero.level)に あがった！", "さいだいHP+\(hp)  さいだいMP+\(mp)", "こうげき+\(atk)  ぼうぎょ+\(def)"]
            await wait(1.6)
        }
        endBattle()
    }

    private func defeat() async {
        messages = ["ゆうしゃは ちからつきた……。"]
        await wait(1.6)
        hero.restore()
        position = WorldMap.start
        facing = .north
        lastTile = .castle
        endBattle()
        messages = ["……気がつくと 城のベッドの上だった。", "王さま「むりは ならぬぞ。」"]
    }

    private func endBattle() {
        enemy = nil
        mode = .field
        phase = .idle
        messages = []
        scene.showField(hero: WorldMap.world(position), yaw: facing.yaw)
    }

    private func roll(_ attack: Int, against defense: Int) -> Int {
        let base = Float(attack) - Float(defense) / 2
        return max(Int((base * Float.random(in: 0.8...1.2)).rounded()), Int.random(in: 0...1))
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}

enum BattleCommand: Equatable {
    case attack, spells, defend, run, back
    case cast(Spell)
}
