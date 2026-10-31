import RealityKit
import SwiftUI

struct ContentView: View {
    @State private var game = Game()
    @State private var updates: EventSubscription?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RealityView { content in
                content.camera = .virtual
                content.add(game.scene.root)
                updates = content.subscribe(to: SceneEvents.Update.self) { event in
                    let dt = Float(min(event.deltaTime, 1.0 / 20))
                    MainActor.assumeIsolated { game.tick(dt) }
                }
            }
            .ignoresSafeArea()
            .modifier(Shake(amount: game.shakeCount))
            .animation(.linear(duration: 0.35), value: game.shakeCount)

            FlashOverlay(trigger: game.flashCount)

            switch game.mode {
            case .loading:
                LoadingView(error: game.loadError)
            case .title:
                TitleView { game.startAdventure() }
            case .field:
                FieldHUD(game: game)
            case .battle:
                BattleHUD(game: game)
            case .ending:
                EndingView { game.backToTitle() }
            }
        }
        .preferredColorScheme(.dark)
        .task { await game.load() }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .up]) { press in
            let direction: Direction? = switch press.key {
            case .upArrow: .north
            case .downArrow: .south
            case .leftArrow: .west
            case .rightArrow: .east
            default: nil
            }
            guard let direction else { return .ignored }
            if press.phase == .up {
                if game.heldDirection == direction { game.heldDirection = nil }
            } else {
                game.heldDirection = direction
            }
            return .handled
        }
    }
}

// MARK: - Windows

/// The classic black window with a white rounded border.
struct RPGWindow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.02, green: 0.02, blue: 0.08).opacity(0.88), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white, lineWidth: 3))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.35), lineWidth: 1).padding(5))
            .foregroundStyle(.white)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
    }
}

struct StatusWindow: View {
    let hero: HeroStats

    var body: some View {
        RPGWindow {
            VStack(alignment: .leading, spacing: 3) {
                Text("ゆうしゃ").font(.system(size: 15, weight: .heavy, design: .rounded))
                Text("Lv \(hero.level)")
                Text("HP \(hero.hp)/\(hero.maxHP)")
                    .foregroundStyle(hero.hp * 4 <= hero.maxHP ? Color.orange : Color.white)
                Text("MP \(hero.mp)/\(hero.maxMP)")
            }
            .monospacedDigit()
        }
        .frame(width: 140)
    }
}

struct MessageWindow: View {
    let lines: [String]

    var body: some View {
        RPGWindow {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.suffix(3).enumerated()), id: \.offset) { _, line in
                    Text(line).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: 72, alignment: .topLeading)
        }
        .transition(.opacity)
    }
}

// MARK: - Field

struct FieldHUD: View {
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                StatusWindow(hero: game.hero)
                Spacer()
                if let next = game.hero.expToNext {
                    RPGWindow { Text("つぎのLvまで \(next)").monospacedDigit() }
                        .frame(width: 170)
                }
            }
            Spacer()
            if !game.messages.isEmpty {
                MessageWindow(lines: game.messages)
            }
            HStack {
                Spacer()
                DPad(held: Binding(get: { game.heldDirection }, set: { game.heldDirection = $0 }))
            }
        }
        .padding(16)
        .animation(.easeOut(duration: 0.2), value: game.messages)
    }
}

struct DPad: View {
    @Binding var held: Direction?

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow { Color.clear.frame(width: 1, height: 1); key(.north, "arrowtriangle.up.fill"); Color.clear.frame(width: 1, height: 1) }
            GridRow { key(.west, "arrowtriangle.left.fill"); Circle().fill(.white.opacity(0.15)).frame(width: 26); key(.east, "arrowtriangle.right.fill") }
            GridRow { Color.clear.frame(width: 1, height: 1); key(.south, "arrowtriangle.down.fill"); Color.clear.frame(width: 1, height: 1) }
        }
        .padding(8)
        .background(.black.opacity(0.35), in: .circle)
    }

    private func key(_ direction: Direction, _ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22))
            .foregroundStyle(.white)
            .frame(width: 54, height: 54)
            .background(held == direction ? Color.white.opacity(0.4) : Color.white.opacity(0.15), in: .rect(cornerRadius: 12))
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in held = direction }
                    .onEnded { _ in if held == direction { held = nil } }
            )
            .accessibilityLabel(Text(label(direction)))
            .accessibilityAddTraits(.isButton)
    }

    private func label(_ d: Direction) -> String {
        switch d {
        case .north: "上"
        case .south: "下"
        case .east: "右"
        case .west: "左"
        }
    }
}

// MARK: - Battle

struct BattleHUD: View {
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                StatusWindow(hero: game.hero)
                Spacer()
                if let enemy = game.enemy {
                    EnemyGauge(name: enemy.name, hp: game.enemyHP, maxHP: enemy.maxHP)
                }
            }
            Spacer()
            if game.phase == .command || game.phase == .spells {
                CommandWindow(game: game)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            MessageWindow(lines: game.messages)
        }
        .padding(16)
        .animation(.easeOut(duration: 0.18), value: game.phase)
    }
}

struct EnemyGauge: View {
    let name: String
    let hp: Int
    let maxHP: Int

    var body: some View {
        RPGWindow {
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(Color(red: 0.95, green: 0.3, blue: 0.3))
                            .frame(width: proxy.size.width * CGFloat(max(hp, 0)) / CGFloat(maxHP))
                    }
                }
                .frame(height: 8)
                .animation(.easeOut(duration: 0.4), value: hp)
            }
        }
        .frame(width: 170)
    }
}

struct CommandWindow: View {
    let game: Game

    var body: some View {
        RPGWindow {
            if game.phase == .spells {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        spell(.heal)
                        spell(.fire)
                    }
                    GridRow {
                        command("もどる", .back)
                        Color.clear.frame(height: 1)
                    }
                }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        command("たたかう", .attack)
                        command("じゅもん", .spells)
                    }
                    GridRow {
                        command("ぼうぎょ", .defend)
                        command("にげる", .run)
                    }
                }
            }
        }
        .font(.system(size: 19, weight: .bold, design: .rounded))
    }

    private func spell(_ spell: Spell) -> some View {
        command("\(spell.name)  \(spell.cost)", .cast(spell), enabled: game.hero.mp >= spell.cost)
    }

    private func command(_ title: String, _ command: BattleCommand, enabled: Bool = true) -> some View {
        Button {
            game.choose(command)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill").font(.system(size: 11))
                Text(title)
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: - Title / ending / loading

struct TitleView: View {
    let start: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer().frame(height: 60)
            VStack(spacing: 4) {
                Text("REALITIZER")
                    .font(.system(size: 20, weight: .heavy, design: .serif))
                    .tracking(8)
                Text("QUEST")
                    .font(.system(size: 54, weight: .black, design: .serif))
                    .tracking(6)
                Text("黒竜と はじまりの国")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundStyle(
                LinearGradient(colors: [Color(red: 1, green: 0.92, blue: 0.6), Color(red: 0.95, green: 0.62, blue: 0.2)],
                               startPoint: .top, endPoint: .bottom)
            )
            .shadow(color: .black.opacity(0.8), radius: 6, y: 3)
            Spacer()
            Button(action: start) {
                Text("ぼうけんを はじめる")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.7), in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white, lineWidth: 3))
            }
            .buttonStyle(.plain)
            Text("3D models are generated in Swift with Realitizer")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 24)
        }
    }
}

struct EndingView: View {
    let restart: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 50)
            RPGWindow {
                VStack(alignment: .leading, spacing: 8) {
                    Text("黒竜ヴァルグは たおれ、")
                    Text("国に ふたたび 朝が おとずれた。")
                    Text("ゆうしゃの 名は 長く 語りつがれたという。")
                }
            }
            Spacer()
            Text("THE END")
                .font(.system(size: 44, weight: .black, design: .serif))
                .foregroundStyle(.white)
                .shadow(radius: 6)
            Button("タイトルへ", action: restart)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.7))
                .padding(.bottom, 30)
        }
        .padding(16)
    }
}

struct LoadingView: View {
    let error: String?

    var body: some View {
        VStack(spacing: 12) {
            if let error {
                Text("読み込みに失敗しました").font(.headline)
                Text(error).font(.caption.monospaced()).padding()
            } else {
                ProgressView().tint(.white)
                Text("モデルを生成中…").font(.headline)
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Effects

struct Shake: GeometryEffect {
    var amount: Int
    var animatableData: CGFloat

    init(amount: Int) {
        self.amount = amount
        animatableData = CGFloat(amount)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let phase = animatableData - floor(animatableData)
        let x = sin(phase * .pi * 8) * 12 * (1 - phase)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

struct FlashOverlay: View {
    let trigger: Int
    @State private var opacity = 0.0

    var body: some View {
        Color.white
            .opacity(opacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: trigger) {
                opacity = 0.9
                withAnimation(.easeOut(duration: 0.5)) { opacity = 0 }
            }
    }
}
