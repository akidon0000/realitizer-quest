# Realitizer Quest

[koher/realitizer](https://github.com/koher/realitizer) で 3D モデルをすべて Swift コードから生成して作った、見下ろし型フィールドとコマンドバトルの RPG（iOS）。画像や 3D ファイルは一切使っていない。キャラクター・モンスター・世界観はすべてオリジナル。

## 遊び方

- 十字キー（シミュレーターでは矢印キーも可）でフィールドを歩く。草原と森ではランダムに敵が出る
- 町 🏠 と城 🏰 に入ると HP/MP が全回復する。城の王さまは次のレベルまでの経験値を教えてくれる
- 北東の山にある紫の祭壇が炎竜ヴァルグの巣。倒すとエンディング（目安は Lv 7〜8）
- タイトルの「モンスター図鑑」で全モンスターの 3D モデルを見られる。ドラッグで回転、ピンチで拡大縮小、モーション再生、ワイヤーフレーム/パーツ色分け表示に切り替えられる
- 戦闘コマンドは「たたかう / じゅもん（ヒール・ファイア）/ ぼうぎょ / にげる」

## 3D モデル

| ファイル | 中身 |
|---|---|
| `Models/HeroModel.swift` | 主人公（兜・マント・剣・盾）と歩行/待機クリップ |
| `Models/MonsterModels.swift` | モコリン・キノコロ・ヨロイガニ。各モデルに idle / attack / hurt クリップ |
| `Models/DragonModel.swift` | 炎竜ヴァルグ。胴・首・尾は 9 関節で曲がるスキンメッシュ、頭・顎・角・翼・脚は関節に付く剛体パーツ。頭蓋パーツ（skull）の鼻先にゲーム側で炎のパーティクルを付ける |
| `Models/FieldModels.swift` | `WorldMap` から組み立てるフィールド一式、戦闘ステージ 3 種、戦闘エフェクト |

各ファイル末尾の `#Preview` で `ModelAssetPreview` を使って単体表示できる。モデルはパーツ階層（`ModelPartDefinition` の parent）で組み、アニメーションは `AnimationClipDefinition.bake` でパーツの transform を焼き込み、実行時は `RuntimeModelInstance.sample(_:at:)` で再生している。

## ビルド

Xcode 27 / iOS 26 以降。プロジェクトは XcodeGen で生成する。

```bash
xcodegen generate
open RealitizerQuest.xcodeproj
```

realitizer がシェーダーを同梱しているため、初回は Metal Toolchain が要る（`xcodebuild -downloadComponent MetalToolchain`）。

起動引数 `-debugBattle <mokorin|kinokoro|yoroigani|varg>` を付けると、タイトルを飛ばしてその敵との戦闘から始まる（`varg` は Lv 8・ボス HP 1/5 で始まるのでエンディングの確認に使える）。`-bestiary <0-3>` で図鑑の該当ページから始まる。
