# バトルアイテム付き鬼ごっこ（Roblox）

ラウンド制の鬼ごっこに、マップに出てくる「バトルアイテム」を組み合わせた Roblox ゲームです。
スクリプト一式を Rojo 形式でまとめています。マップは Roblox Studio 側で自由に作ってください。

## ゲームの説明

1. **待機**: 2人以上そろうと、15秒のインターミッションが始まります。人数が足りない間は画面に「あと○人」と出ます。
2. **鬼の選出**: 参加者の中からランダムに1人が鬼になります。
3. **ラウンド（120秒）**: 鬼が逃げる人にタッチすると、タッチされた人が次の鬼になります。
   - 鬼になった直後の3秒間はタッチできません（タッチ返し防止）。
   - 鬼は少し足が速くなります（WalkSpeed 20。通常は16）。
4. **結果表示**: ラウンド中に一度も鬼にならずに逃げ切った人が勝ちです。
5. 待機に戻り、これを繰り返します。

ラウンド中に入ってきた人は、次のラウンドから参加します（それまでは観戦扱い）。
ラウンド中に人数が2人を下回ったら、そのラウンドは中止して待機に戻ります（勝ちは記録されません）。

### 記録（leaderstats）

プレイヤーリストに2つの項目が出ます。

| 項目 | 増えるとき |
|---|---|
| 逃げ切り | ラウンド終了まで一度も鬼にならなかった |
| 鬼タッチ | ラウンド中に鬼にタッチされて鬼になった（最初にランダムで選ばれた鬼は数えません） |

※ 記録はサーバーにいる間だけです（DataStore での保存はしていません）。

## バトルアイテム

ラウンド中、マップの出現ポイントに10秒ごとにランダムで1つ出てきます（同時に最大3つ）。
触れると拾えます。持てるのは1つだけです。

| アイテム | 効果 | 鬼が使えるか |
|---|---|---|
| ダッシュ | 5秒間 WalkSpeed が 26 になる | 使える |
| スモーク | 鬼の画面を3秒間まっ白にする | 使えない（自分に効くため） |
| シールド | 1回だけタッチを防ぐ（10秒で消える）。防いだ直後1.5秒は続けてタッチされない | 使えない |
| ワープ | ランダムな出現ポイントへ瞬間移動する | 使える |

## 遊び方（操作）

- 移動・ジャンプは Roblox の通常操作です。
- アイテムを使う: **E キー**、ゲームパッドの **X ボタン**、または画面右下の**アイテムボタン**（スマホはタップ）。
- 画面上部に「今のフェーズ」「残り時間」「自分の役割（鬼／逃げる人／観戦中）」が出ます。

## ファイル構成

```
default.project.json          Rojo のプロジェクト定義
src/
  shared/                     → ReplicatedStorage.Shared
    Config.lua                  設定モジュール（時間・速度・アイテム定義）★数字はここで変える
  server/                     → ServerScriptService.Server
    Main.server.lua             起動スクリプト（各モジュールを初期化してラウンドを回す）
    RoundManager.lua            ラウンド進行、鬼の選出、タッチ判定
    ItemManager.lua             アイテムの出現・拾う処理・効果
    GameState.lua               ラウンドとプレイヤーの状態、移動速度の決定
    Leaderstats.lua             「逃げ切り」「鬼タッチ」の記録
    Remotes.lua                 RemoteEvent の作成
  client/                     → StarterPlayer.StarterPlayerScripts.Client
    HUD.client.lua              役割・残り時間・人数待ち・結果・お知らせの表示
    ItemControls.client.lua     アイテムボタンとキー入力、効果の残り時間表示
    SmokeEffect.client.lua      スモークを受けたときの白い画面
```

ファイル名の `.server.lua` は Script、`.client.lua` は LocalScript、それ以外の `.lua` は ModuleScript になります。

### 通信と判定の考え方

- RemoteEvent はサーバー起動時に `ReplicatedStorage.Remotes` フォルダに自動で作られます（Studio で用意する必要はありません）。
- クライアントから送るのは「アイテムを使いたい」（`UseItem`）だけです。何を持っているか、使えるか、効果がどうなるかは、すべてサーバーが決めます。
- タッチ判定はサーバーが鬼と逃げる人の距離（`Config.TagDistance`、初期値5スタッド）を0.1秒ごとに測って行います。

## Roblox Studio での開き方

### 方法A: Rojo を使う（おすすめ）

1. Rojo をインストールします（https://rojo.space/ の手順。Aftman / Rokit / Foreman などのツール管理を使う方法と、VS Code 拡張を使う方法があります）。
2. Roblox Studio に Rojo プラグインを入れます（Rojo の公式手順、または `rojo plugin install`）。
3. このフォルダでサーバーを起動します。
   ```
   rojo serve
   ```
4. Studio でマップの place を開き、Rojo プラグインの「Connect」を押すと、スクリプトが同期されます。
5. ファイルを編集すると、Studio に自動で反映されます。

place ファイルを丸ごと作りたい場合は `rojo build -o TagBattle.rbxlx` で書き出して Studio で開けます（この場合マップは空なので、Studio 側で作ってください）。

### 方法B: ファイルを手で配置する

Rojo を使わない場合は、Studio の Explorer で次のように作って、各ファイルの中身をコピー＆ペーストします。
**オブジェクト名はファイル名から拡張子（`.server.lua` / `.client.lua` / `.lua`）を取ったもの**にしてください（スクリプト同士が名前で探し合うため）。

| Studio での場所 | 作るもの | 中身 |
|---|---|---|
| ReplicatedStorage | Folder `Shared` | |
| ReplicatedStorage › Shared | ModuleScript `Config` | `src/shared/Config.lua` |
| ServerScriptService | Folder `Server` | |
| ServerScriptService › Server | Script `Main` | `src/server/Main.server.lua` |
| ServerScriptService › Server | ModuleScript `RoundManager` | `src/server/RoundManager.lua` |
| ServerScriptService › Server | ModuleScript `ItemManager` | `src/server/ItemManager.lua` |
| ServerScriptService › Server | ModuleScript `GameState` | `src/server/GameState.lua` |
| ServerScriptService › Server | ModuleScript `Leaderstats` | `src/server/Leaderstats.lua` |
| ServerScriptService › Server | ModuleScript `Remotes` | `src/server/Remotes.lua` |
| StarterPlayer › StarterPlayerScripts | Folder `Client` | |
| StarterPlayer › StarterPlayerScripts › Client | LocalScript `HUD` | `src/client/HUD.client.lua` |
| StarterPlayer › StarterPlayerScripts › Client | LocalScript `ItemControls` | `src/client/ItemControls.client.lua` |
| StarterPlayer › StarterPlayerScripts › Client | LocalScript `SmokeEffect` | `src/client/SmokeEffect.client.lua` |

### テストのしかた

2人以上必要なので、Studio の「テスト」タブ →「クライアントとサーバー」でプレイヤー数を2〜3にして「開始」すると、ローカルで複数人のテストができます。

## マップ側の準備（ItemSpawns フォルダ）

1. マップ（床・障害物・SpawnLocation など）を Studio で作ります。
2. Explorer で **Workspace** を右クリック →「オブジェクトを挿入」→ **Folder** を追加し、名前を **`ItemSpawns`** にします。
3. アイテムを出したい場所に **Part** を置き、`ItemSpawns` フォルダの中に入れます（何個でも可。フォルダの中のフォルダに入れても拾われます）。
   - アイテムは Part の中心から3スタッド上に出ます。
   - 目印用の Part は `Anchored = true`、`CanCollide = false`、`Transparency = 1` にしておくと邪魔になりません。
4. ワープの移動先にも、この出現ポイントが使われます。

`ItemSpawns` フォルダがない、または中に Part がない場合でも、エラーにはならず、原点付近（`Config.FallbackSpawnCenter` のまわり）にアイテムが出ます。そのとき Output に警告が1回だけ出ます。

## 数字の変え方

数字はすべて **`src/shared/Config.lua`**（Studio では `ReplicatedStorage › Shared › Config`）にまとまっています。ここを書き換えるだけで反映されます。

| 変えたいもの | 設定名 | 初期値 |
|---|---|---|
| 最低人数 | `Config.MinPlayers` | 2 |
| 待機時間 | `Config.IntermissionTime` | 15 |
| ラウンド時間 | `Config.RoundTime` | 120 |
| 結果表示の時間 | `Config.ResultsTime` | 6 |
| 通常の速さ / 鬼の速さ | `Config.NormalWalkSpeed` / `Config.TaggerWalkSpeed` | 16 / 20 |
| 鬼になった直後のタッチ無効時間 | `Config.TagCooldown` | 3 |
| タッチになる距離 | `Config.TagDistance` | 5 |
| アイテムの出現間隔 / 同時最大数 | `Config.ItemSpawnInterval` / `Config.MaxItemsOnMap` | 10 / 3 |
| アイテム使用キー | `Config.UseItemKeys`（表示名は `Config.UseItemKeyLabel`） | E / ゲームパッドX |
| leaderstats の項目名 | `Config.LeaderstatNames` | 逃げ切り / 鬼タッチ |

アイテムごとの数字は `Config.Items` の中にあります。

- `Config.Items.Dash.Duration` / `WalkSpeed`: ダッシュの時間と速さ（5秒 / 26）
- `Config.Items.Smoke.Duration`: 鬼の画面が白くなる時間（3秒）
- `Config.Items.Shield.Duration` / `GraceTime`: シールドが残る時間（10秒）と、防いだ直後の無敵時間（1.5秒）
- `Config.Items.Warp.HeightOffset`: ワープ先の高さ
- 各アイテムの `DisplayName`（表示名）、`Description`（説明文）、`Color`（色）、`SpawnWeight`（出やすさ。0 にするとそのアイテムは出なくなる）、`CanTaggerUse`（鬼が使えるか）

## 注意

- 移動はクライアント側の物理で動くため、チート対策（速度の改ざん検知など）までは入れていません。タッチ判定・アイテムの所持と効果はサーバーで確定しています。
- 記録の永続保存（DataStore）は入っていません。必要なら `Leaderstats.lua` に追加してください。
