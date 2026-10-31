import SwiftUI

extension MonsterKind {
    var bestiaryText: String {
        switch self {
        case .mokorin: "花粉が まるまって 生まれた ふわふわの魔物。頭の葉っぱで 風をよみ、はねるように 体当たりしてくる。"
        case .kinokoro: "森の木かげに むらがる 歩くキノコ。いつも 不機嫌そうな顔で、ちいさな腕を ふりまわす。"
        case .yoroigani: "トゲだらけの こうらを持つ 大ガニ。重いハサミの一撃は 旅人の盾をも へこませる。"
        case .varg: "北東の山に すみついた 炎の竜。のどの奥に 燃える火を たくわえ、大きく 息をすうと 灼熱のほのおを はきだす。"
        }
    }

    /// Clips shown as buttons in the bestiary, with their labels.
    var bestiaryClips: [(clip: String, label: String)] {
        var clips = [("idle", "たいき"), ("attack", "こうげき"), ("hurt", "ひるむ")]
        if self == .varg { clips.append(("breath", "ほのお")) }
        return clips
    }
}

struct BestiaryView: View {
    let game: Game
    @State private var lastDrag: CGSize = .zero
    @State private var pinchBase: Float?

    private var kind: MonsterKind { MonsterKind.allCases[game.bestiaryIndex] }

    var body: some View {
        VStack(spacing: 10) {
            header
            ZStack {
                Color.clear.contentShape(.rect).gesture(orbit).simultaneousGesture(zoom)
                HStack {
                    arrow("chevron.left") { game.showBestiaryEntry(game.bestiaryIndex - 1) }
                    Spacer()
                    arrow("chevron.right") { game.showBestiaryEntry(game.bestiaryIndex + 1) }
                }
            }
            displayPicker
            entryCard
        }
        .padding(16)
    }

    private var header: some View {
        HStack {
            Button { game.backToTitle() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.6), in: .circle)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("とじる")
            Spacer()
            Text("モンスター図鑑")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
            Spacer()
            Text("No.\(game.bestiaryIndex + 1)/\(MonsterKind.allCases.count)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.7), radius: 3)
    }

    private var displayPicker: some View {
        HStack(spacing: 6) {
            ForEach(GameScene.Display.allCases, id: \.self) { display in
                let selected = game.bestiaryDisplay == display
                Button { game.setBestiaryDisplay(display) } label: {
                    Text(label(display))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(selected ? .black : .white)
                        .background(selected ? Color.white : Color.black.opacity(0.6), in: .capsule)
                        .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0 : 0.7), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var entryCard: some View {
        RPGWindow {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(kind.name).font(.system(size: 22, weight: .heavy, design: .rounded))
                    if kind.isBoss {
                        Text("BOSS")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(red: 0.85, green: 0.2, blue: 0.1), in: .capsule)
                    }
                }
                Text(kind.bestiaryText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    stat("HP", kind.maxHP)
                    stat("こうげき", kind.attack)
                    stat("ぼうぎょ", kind.defense)
                    if !kind.isBoss { stat("けいけんち", kind.exp) }
                }
                if let stats = game.scene.statistics(of: kind) {
                    Text("頂点 \(stats.vertices) ・ 三角形 \(stats.triangles) ・ パーツ \(stats.parts)" + (stats.joints > 0 ? " ・ 関節 \(stats.joints)" : ""))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
                HStack(spacing: 8) {
                    ForEach(kind.bestiaryClips, id: \.clip) { item in
                        Button { game.playBestiaryClip(item.clip) } label: {
                            Text(item.label)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(.white.opacity(item.clip == "breath" ? 0 : 0.12), in: .rect(cornerRadius: 8))
                                .background(
                                    LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                                        .opacity(item.clip == "breath" ? 0.85 : 0),
                                    in: .rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.65))
            Text("\(value)").font(.system(size: 17, weight: .heavy, design: .rounded)).monospacedDigit()
        }
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.45), in: .circle)
        }
        .buttonStyle(.plain)
    }

    private func label(_ display: GameScene.Display) -> String {
        switch display {
        case .shaded: "通常"
        case .wireframe: "ワイヤー"
        case .parts: "パーツ色分け"
        }
    }

    private var orbit: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let dx = Float(value.translation.width - lastDrag.width)
                let dy = Float(value.translation.height - lastDrag.height)
                lastDrag = value.translation
                game.scene.inspectYaw -= dx * 0.01
                game.scene.inspectPitch = min(max(game.scene.inspectPitch + dy * 0.008, -0.15), 1.3)
            }
            .onEnded { _ in lastDrag = .zero }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBase ?? game.scene.inspectDistance
                pinchBase = base
                let limit: ClosedRange<Float> = kind.isBoss ? 3...14 : 1...5
                game.scene.inspectDistance = min(max(base / Float(value.magnification), limit.lowerBound), limit.upperBound)
            }
            .onEnded { _ in pinchBase = nil }
    }
}
