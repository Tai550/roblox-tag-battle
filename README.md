# バトルアイテム付き鬼ごっこ（Roblox）

ラウンド制の鬼ごっこに、マップに出てくる「バトルアイテム」を組み合わせた Roblox ゲームです。
スクリプト一式を Rojo 形式でまとめています。マップはサーバー起動時にコードで自動生成されます。渋谷 → パーク → 洞窟 → 氷床 → 痺れるダンジョン → 落下ダンジョンの順で6マップを巡回します（[マップ（コード生成）](#マップコード生成) を参照）。

## ゲームの説明

1. **待機**: 2人以上そろうと、15秒のインターミッションが始まります。人数が足りない間は画面に「あと○人」と出ます。
2. **試合時間の投票**: インターミッション中に、試合時間（1分／3分／5分）を投票で決めます。最多票の時間が採用され、同数のときと誰も投票しなかったときは3分になります。
3. **鬼の選出**: 参加者の中からランダムに1人が鬼になります。
4. **ラウンド（投票で決まった時間）**: 鬼が逃げる人にタッチすると、タッチされた人が次の鬼になります。
   - 鬼の手が届く範囲で、相手の体のどこか（アクセサリも含む）に触れるとタッチ成立です。
   - 鬼になった直後の3秒間はタッチできません（タッチ返し防止）。
   - 鬼は少し足が速くなります（WalkSpeed 20。通常は16）。
   - 鬼のキャラクターは少し赤みがかった色になり、体に薄い赤い光（輪郭つきの Highlight）が付きます。鬼でなくなると元の色に戻ります。リスポーンしても、鬼のあいだは付け直されます。
   - **エリアが縮みます**: ピンクの円柱の壁で示されるエリアが、試合時間の80%をかけて半径18まで縮み続けます。エリアの外に出続けると専用スタミナが減り、0になるとエリアの中へ戻されます（脱落にはなりません）。
5. **結果表示**: ラウンド中に一度も鬼にならずに逃げ切った人が勝ちです。
6. 待機に戻り、これを繰り返します。

ラウンド中に入ってきた人は、次のラウンドから参加します（それまでは観戦扱い）。
人間が全員抜けるか、参加者（ボットを含む）が2人を下回ったら、そのラウンドは中止して待機に戻ります（勝ちは記録されません）。

### 人数が足りないときのボット

人間が2人以上いて、8人未満のとき、足りない分をボット（NPC）が参加者に加わります。例として、人間が3人ならボットは5体です。人間が1人以下のときは、これまでどおりラウンドは始まりません。ボットだけでは始まりません。人間がすでに8人以上なら、ボットは入りません（`Config.BotsEnabled` を false にすると、補充そのものを止められます）。

ボットの名前は「ボット1」から順に付きます。頭の上に名前が出て、体は薄い灰色で、人間のアバターと見分けられます。鬼になったときは、人間と同じく少し赤くなり、体に Highlight が付きます。ラウンドが終わるとボットは消えます。サーバーには残りません。

ボットは段位の保存、課金、デッキの変更、試合時間の投票には参加しません。画面への通知も飛びません。タッチされて鬼が交代する流れは人間と同じです。逃げ切りや捕獲の RP と、逃げ切り・鬼タッチの記録は人間にだけ付きます。

ボットの歩く速さと、経路を引き直す間隔は、そのサーバーにいる人間の平均段位に合わせて少し変わります。段位が高いほど速さの倍率は上がり、経路の引き直しは短くなります。倍率の上限は 1.15 です。これは機械学習ではありません。段位ごとの表（`Config.BotStrengthByTier`）を引くだけの段階的な調整です。

### 記録（leaderstats）

プレイヤーリストに4つの項目が出ます。逃げ切り・鬼タッチ・RP は累計で、次に入ったときも続きから表示されます（[段位](#段位ランク)）。

| 項目 | 意味 |
|---|---|
| 逃げ切り | ラウンド終了まで一度も鬼にならなかった回数 |
| 鬼タッチ | ラウンド中に鬼にタッチされて鬼になった回数（最初にランダムで選ばれた鬼は数えません） |
| ランク | 今の段位名（例: ゴールド） |
| RP | 累計ランクポイント |

### 段位（ランク）

遊ぶほど **ランクポイント（RP）** が貯まり、累計で段位が上がります。RPは減りません（降格はありません）。

| 段位 | 累計RP |
|---|---|
| ブロンズ | 0 |
| シルバー | 100 |
| ゴールド | 250 |
| プラチナ | 500 |
| ダイヤ | 850 |
| マスター | 1300 |

| できごと | RP |
|---|---|
| 逃げ切り（最後まで捕まらなかった） | +20 |
| 鬼が1人捕まえる | +6 |
| 鬼が全員捕まえた | +14（追加） |
| 捕まった | +4 |

「鬼が全員捕まえた」は、ラウンドが最後まで行われて逃げ切った人が一人もいないとき、**最後の未タッチ者をタッチした鬼**に追加されます。ラウンドが人数不足で中止したときは、逃げ切りの +20 も、この +14 も入りません（それまでに入った「1人捕まえる +6」と「捕まった +4」はそのままです）。

画面上部に、自分の段位・RP・「次の段位まであと◯RP」が1行で出ます（最高段のマスターは「最高段位」）。段位が上がった瞬間だけ「ランクアップ！ ◯◯に昇格」と数秒出ます。

#### 保存

`RankManager` が DataStore **`RankV1`** に、プレイヤーごとに `{ RP, Survived, Tagged }` を保存します。キーは UserId を文字列にしたものです。「逃げ切り」「鬼タッチ」もこの累計に含まれます。

保存するタイミング:

- プレイヤーが抜けたとき
- サーバーが閉じるとき（`BindToClose`）
- 180秒ごと（そのときサーバーにいる全員。`Config.RankSaveInterval`）

読み込みは参加したときです。保存も読み込みも失敗しても試合は止まりません（Output に警告が出ます）。読み込みに失敗したときは、その参加では 0 から表示します。失敗したままの保存は行わないので、通信エラーでそれまでの累計を 0 で上書きすることはありません。

**Studio で保存を試すには**、Game Settings → Security →「Enable Studio Access to API Services」をオンにしてください。オフのままだと DataStore が使えず、段位はその回 0 から始まり、記録は残りません。

## バトルアイテムとデッキ

通常アイテムは6種あります。各プレイヤーはその中から3つを選んで**デッキ**を作ります（画面左下の「デッキ」ボタン。選んでいない人のデッキは ダッシュ／シールド／ワープ です）。

ラウンド中、出現ポイントに10秒ごとに**アイテムボックス**が1つ出てきます（同時に最大3つ。縮小エリアの内側にだけ出ます）。
ボックスに触れると、自分のデッキと現在のマップの固有アイテムからランダムで1つ手に入ります。通常アイテムと手動で使う固有アイテムには**15秒の使用期限**があります。命綱は発動、持ち物の入れ替え、ラウンド終了のいずれかまで持てます。
フィールドに出る箱は、光る立方体ではなく木の宝箱です（金色の帯と鍵穴、蓋の境目の細い光）。置かれているあいだ、ゆっくり上下して回転します。触って中身が手に入る動きは今までどおりです。
持てるのは1つだけです（ゲームパス「ダブルアイテム」を持っていると2つまで。枠が空いていれば拾えます）。

※ ショップで買う「アイテムボックス」は今までどおりで、全アイテムの中からランダムに1つ手に入り、使用期限はありません。

| アイテム | 効果 | 鬼が使えるか |
|---|---|---|
| ダッシュ | 5秒間 WalkSpeed が 26 になる | 使える |
| スモーク | 鬼の画面を3秒間まっ白にする | 使えない（自分に効くため） |
| シールド | 1回だけタッチを防ぐ（10秒で消える）。防いだ直後1.5秒は続けてタッチされない | 使えない |
| ワープ | ランダムな出現ポイントへ瞬間移動する | 使える |
| スター | 4秒間、鬼にタッチされなくなる | 使えない |
| バナナ | 足元に置く。置いた本人以外の人が踏むと、1.2秒間すべる（置いてから20秒で消える） | 使える |

## 遊び方（操作）

- 移動・ジャンプは Roblox の通常操作です。
- アイテムを使う: 画面右下の**アイテムボタン**（スマホはタップ）、またはキー入力。
  - 1枠目: **E キー** / ゲームパッドの **X ボタン** / 右側のボタン
  - 2枠目（ダブルアイテム所有者のみ）: **Q キー** / ゲームパッドの **Y ボタン** / 左側のボタン
  - 1枠目を使うと、2枠目のアイテムが1枠目に繰り上がります。
- 画面左の**ショップ**ボタンで、課金商品の一覧を開けます（[課金](#課金) を参照）。
- 画面上部に「今のフェーズ」「残り時間」「自分の役割（鬼／逃げる人／観戦中）」と、自分の段位・RP・次の段位まであと何RPかが出ます。
- インターミッション中は、画面上の**投票ボタン**（1分／3分／5分）で試合時間を投票できます。
- 画面左下の**デッキ**ボタンで、ボックスから出るアイテムの組み合わせ（3つ）をいつでも変えられます。
- ラウンド中は画面右上に「エリアの大きさ」とエリア外スタミナが出ます。エリアの外にいると警告が出ます。

## ファイル構成

```
default.project.json          Rojo のプロジェクト定義
src/
  shared/                     → ReplicatedStorage.Shared
    Config.lua                  設定モジュール（時間・速度・アイテム定義）★数字はここで変える
    UILayout.lua                スマホ向けの寸法表と安全領域の設定
  server/                     → ServerScriptService.Server
    Main.server.lua             起動スクリプト（各モジュールを初期化してラウンドを回す）
    RoundManager.lua            ラウンド進行、鬼の選出、タッチ判定、試合時間の投票集計
    BotManager.lua              人数不足をボットで補う（移動・拾う・強さの調整）
    ItemManager.lua             ボックスの出現・拾う処理・アイテムの効果
    GameState.lua               ラウンドとプレイヤーの状態、移動速度の決定
    Leaderstats.lua             「逃げ切り」「鬼タッチ」「ランク」「RP」の表示
    RankManager.lua             段位の累計と DataStore への保存
    Remotes.lua                 RemoteEvent の作成
    AdminManager.lua            管理操作の権限判定、BAN、操作履歴
    Monetization.lua            課金：レシート処理（アイテムボックス）、Game Pass の所有確認
    SparkleTrail.lua            キラキラトレイルの付け外し（見た目だけ）
    TaggerLook.lua              鬼の見た目（少し赤い色と Highlight の付け外し）
    ZoneManager.lua             縮小エリア（中心・半径の計算、壁、エリア外スタミナ）
    DeckManager.lua             デッキ構築（選択の検証、デッキからの抽選）
    MapBuilder.lua              6種のマップと出現ポイント（ItemSpawns）をコードで生成
  client/                     → StarterPlayer.StarterPlayerScripts.Client
    HUD.client.lua              役割・残り時間・人数待ち・結果・お知らせの表示
    ItemControls.client.lua     アイテムボタンとキー入力、効果の残り時間表示
    SmokeEffect.client.lua      スモークを受けたときの白い画面
    Shop.client.lua             ショップ画面（開くボタンと商品一覧、購入ダイアログの表示）
    Slide.client.lua            氷床でのプレイヤー移動とスパイクブーツの反映
    MatchUI.client.lua          試合時間の投票、デッキ構築、縮小エリアとスタミナの表示
    AdminUI.client.lua          管理ボタンとパネル
```

ファイル名の `.server.lua` は Script、`.client.lua` は LocalScript、それ以外の `.lua` は ModuleScript になります。

### 通信と判定の考え方

- RemoteEvent はサーバー起動時に `ReplicatedStorage.Remotes` フォルダに自動で作られます（Studio で用意する必要はありません）。
- クライアントから送るのは「○枠目のアイテムを使いたい」（`UseItem`、枠番号だけ）、「Game Pass の所有状態を送って」（`PassUpdate`）、「試合時間への投票」（`DurationVote`、秒数だけ）、「選んだデッキ」（`DeckSelect`、アイテム Id のリスト）が含まれます。集計・検証・所持・効果・課金の付与は、すべてサーバーが決めます。
- 管理パネルの取得・操作には `AdminRequest` を使います。サーバーは各リクエストで送信者の管理権限を確認します。
- 段位が上がったときだけ、サーバーがその人に `RankUp`（新しい段位名）を送ります。段位と RP の常時表示は leaderstats を読むだけで、専用の取得リクエストはありません。
- サーバーは0.1秒ごとに、鬼の胸の少し前にある起点から相手の各パーツの箱の最近接点までの距離を測ります。手が届く範囲は `Config.TagReachForward` と `Config.TagTouchDistance` で調整できます。

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

place ファイルを丸ごと作りたい場合は `rojo build -o TagBattle.rbxlx` で書き出して Studio で開けます（マップはファイルには入っておらず、Play でサーバーが起動したときに生成されます）。

### 方法B: ファイルを手で配置する

Rojo を使わない場合は、Studio の Explorer で次のように作って、各ファイルの中身をコピー＆ペーストします。
**オブジェクト名はファイル名から拡張子（`.server.lua` / `.client.lua` / `.lua`）を取ったもの**にしてください（スクリプト同士が名前で探し合うため）。

| Studio での場所 | 作るもの | 中身 |
|---|---|---|
| ReplicatedStorage | Folder `Shared` | |
| ReplicatedStorage › Shared | ModuleScript `Config` | `src/shared/Config.lua` |
| ReplicatedStorage › Shared | ModuleScript `UILayout` | `src/shared/UILayout.lua` |
| ServerScriptService | Folder `Server` | |
| ServerScriptService › Server | Script `Main` | `src/server/Main.server.lua` |
| ServerScriptService › Server | ModuleScript `RoundManager` | `src/server/RoundManager.lua` |
| ServerScriptService › Server | ModuleScript `BotManager` | `src/server/BotManager.lua` |
| ServerScriptService › Server | ModuleScript `ItemManager` | `src/server/ItemManager.lua` |
| ServerScriptService › Server | ModuleScript `GameState` | `src/server/GameState.lua` |
| ServerScriptService › Server | ModuleScript `Leaderstats` | `src/server/Leaderstats.lua` |
| ServerScriptService › Server | ModuleScript `RankManager` | `src/server/RankManager.lua` |
| ServerScriptService › Server | ModuleScript `Remotes` | `src/server/Remotes.lua` |
| ServerScriptService › Server | ModuleScript `AdminManager` | `src/server/AdminManager.lua` |
| ServerScriptService › Server | ModuleScript `Monetization` | `src/server/Monetization.lua` |
| ServerScriptService › Server | ModuleScript `SparkleTrail` | `src/server/SparkleTrail.lua` |
| ServerScriptService › Server | ModuleScript `TaggerLook` | `src/server/TaggerLook.lua` |
| ServerScriptService › Server | ModuleScript `ZoneManager` | `src/server/ZoneManager.lua` |
| ServerScriptService › Server | ModuleScript `DeckManager` | `src/server/DeckManager.lua` |
| ServerScriptService › Server | ModuleScript `MapBuilder` | `src/server/MapBuilder.lua` |
| StarterPlayer › StarterPlayerScripts | Folder `Client` | |
| StarterPlayer › StarterPlayerScripts › Client | LocalScript `HUD` | `src/client/HUD.client.lua` |
| StarterPlayer › StarterPlayerScripts › Client | LocalScript `ItemControls` | `src/client/ItemControls.client.lua` |
| StarterPlayer › StarterPlayerScripts › Client | LocalScript `SmokeEffect` | `src/client/SmokeEffect.client.lua` |
| StarterPlayer › StarterPlayerScripts › Client | LocalScript `Shop` | `src/client/Shop.client.lua` |
| StarterPlayer › StarterPlayerScripts › Client | LocalScript `Slide` | `src/client/Slide.client.lua` |
| StarterPlayer › StarterPlayerScripts › Client | LocalScript `MatchUI` | `src/client/MatchUI.client.lua` |
| StarterPlayer › StarterPlayerScripts › Client | LocalScript `AdminUI` | `src/client/AdminUI.client.lua` |

### テストのしかた

2人以上必要なので、Studio の「テスト」タブ →「クライアントとサーバー」でプレイヤー数を2にして「開始」すると、ローカルでラウンドが始まります。人間が8人未満なら、足りない分はボットが参加します（2人ならボット6体）。ボットの動き（障害物のよけ方、鬼の追い方、ラウンド後に消えること）は、このプレイで見てください。

段位の保存を試すときは、Game Settings → Security →「Enable Studio Access to API Services」をオンにします。オフだと DataStore が使えず、段位はその回 0 から始まります。

## マップ（コード生成）

サーバー起動時に `MapBuilder.Build()` が渋谷を生成します。各ラウンドの開始直前に `MapBuilder.BuildNextRound()` が呼ばれ、渋谷 → パーク → 洞窟 → 氷床 → 痺れるダンジョン → 落下ダンジョンの順に巡回します。ラウンド開始時にマップ名が通知されます。現在のマップとギミックは Workspace の `CurrentMap` と `CurrentGimmick` 属性で確認できます。

各マップは次のフォルダを生成します。既存のフォルダはマップ入れ替え時に作り直されます。

- `Workspace.Map`
- `Workspace.ItemSpawns` … アイテムの出現ポイント。ItemManager / ZoneManager は試合開始時にこのフォルダを読むので、広いパークでも同じ計算のまま連動します。

### 渋谷（巡回の1番目）

- 220×220 スタッドの渋谷風の街。中心がスクランブル交差点（十字の道路・4方向の横断歩道・中央線）、少し高い歩道の街区、ビル20棟（高さ20〜70）、大型スクリーン「SHIBUYA」のランドマーク、木のある広場、駅前風の広場、植え込み・自販機・バス停・信号機・街灯・バリケードなどの障害物、外周の透明な壁。
  - 低いビル3棟には側面にスロープがあり、屋上に登れます（鬼ごっこの逃げ道）。
  - プレイヤーのスポーン（SpawnLocation）は駅前広場にあります。
- 出現ポイントは12点（交差点・路地・屋上2点・広場など）。

### パーク（巡回の2番目）

- 220×220 スタッドの、広くて見通しのよい公園。地面は芝生。中央に円形の舗装広場があり、プレイヤーのスポーンはそこです。
- 障害物は渋谷より少なく、直線で長く走れるように周囲へ寄せてあります。低い丘、岩、木の群れ、ベンチ、低いフェンス、池に見立てた青い面（歩けますが泳げません）、あずまや、低めの小屋が数棟です。外周は渋谷と同じく透明な壁です。
- 出現ポイントは14点。屋外に、マップ全体へ広く散らしてあります（屋上はありません）。

### ダンジョン（巡回の3〜6番目）

| マップ | 大きさ（スタッド） | ギミック | 固有アイテム |
| --- | --- | --- | --- |
| 洞窟（Cave） | 約200×200 | 暗い石の広間と、松明が照らす狭い通路 | **壁抜け**。2.5秒間、洞窟の内壁をすり抜ける。終了時に内壁に重なっていると使用開始位置へ戻る |
| 氷床（Ice） | 220×220 | 入力を離すと滑りながら減速し、曲がるときも慣性が残る | **スパイクブーツ**。5秒間、使用者の氷上の滑りを止める |
| 痺れるダンジョン（Volt） | 220×220 | 帯電部品に触れると1.2秒間、歩行とジャンプが止まる。回復後2秒間は再発しない | **絶縁**。6秒間、帯電部品に触れても痺れない |
| 落下ダンジョン（Sky） | 約220×220（足場の外端間） | 空中の足場と細い橋を渡る。設定高度を下回ると脱落し、ラウンド終了まで観戦する。鬼が脱落すると残った参加者から鬼を選び直す | **命綱**。持って落ちると、1回だけ自動で最後に立っていた足場へ戻る |

各ダンジョンの出現ポイントは12点です。固有アイテムは対応するマップのフィールドボックスにだけ入り、通常アイテムと同じ重みで抽選されます。ボットも拾えます。固有アイテムの効果を使えるのは人間のプレイヤーです。

氷の滑り方は `src/shared/Config.lua` で調整できます。`IceSlideDecay` を大きくすると入力を離したときに早く止まり、`IceSlideSteering` を大きくすると方向転換が速くなります。落下の判定高度は `FallEliminateY` で調整できます。

注意点:

- **Studio で place を開いただけではマップは見えません。** 「プレイ」などでサーバーが起動したときに生成されます（編集画面には残りません）。
- 乱数は使っていないので、同じ種類のマップは毎回同じ形になります。配置を変えたいときは `MapBuilder.lua` の上のほうにある表（`BUILDINGS`、`ITEM_SPAWNS`、パークの `PARK_SPAWNS` など）の数字を書き換えます。
- `Build()` は、すでに `Workspace.Map` と `Workspace.ItemSpawns` があれば消してから作り直します。Studio で自分で作った `ItemSpawns` フォルダも置き換わるので、自作のマップを使うときは次の手順で無効化してください。
- 自作のマップを使う場合は、`Main.server.lua` の初回生成と `RoundManager.lua` のラウンド開始時のマップ生成・通知を自作マップに合わせて変更し、下の手順で ItemSpawns を用意します。

## マップ側の準備（ItemSpawns フォルダ）

自作のマップを使う場合（`MapBuilder.Build()` の呼び出しを外したとき）の手順です。

1. マップ（床・障害物・SpawnLocation など）を Studio で作ります。
2. Explorer で **Workspace** を右クリック →「オブジェクトを挿入」→ **Folder** を追加し、名前を **`ItemSpawns`** にします。
3. アイテムを出したい場所に **Part** を置き、`ItemSpawns` フォルダの中に入れます（何個でも可。フォルダの中のフォルダに入れても拾われます）。
   - アイテムは Part の中心から3スタッド上に出ます。
   - 目印用の Part は `Anchored = true`、`CanCollide = false`、`Transparency = 1` にしておくと邪魔になりません。
4. ワープの移動先にも、この出現ポイントが使われます。
5. 縮小エリアの中心は出現ポイントの平均、開始半径は「中心から一番遠いポイントまでの距離 + 15」（50〜120の範囲）で決まります。遊ばせたい範囲の外周にポイントを置くと、エリアの大きさもそれに合います。

`ItemSpawns` フォルダがない、または中に Part がない場合でも、エラーにはならず、原点付近（`Config.FallbackSpawnCenter` のまわり）にアイテムが出ます。そのとき Output に警告が1回だけ出ます。

## 数字の変え方

数字はすべて **`src/shared/Config.lua`**（Studio では `ReplicatedStorage › Shared › Config`）にまとまっています。ここを書き換えるだけで反映されます。

| 変えたいもの | 設定名 | 初期値 |
|---|---|---|
| 最低人数（人間） | `Config.MinPlayers` | 2 |
| ボットを含めた目標人数 | `Config.BotFillTarget` | 8 |
| ボット補充のオンオフ | `Config.BotsEnabled` | true |
| ボットの速さ倍率の上限 | `Config.BotSpeedMultiplierCap` | 1.15 |
| 待機時間 | `Config.IntermissionTime` | 15 |
| 試合時間の候補 / 既定値 | `Config.MatchDurations` / `Config.DefaultDuration` | 60・180・300秒 / 180秒 |
| 結果表示の時間 | `Config.ResultsTime` | 6 |
| エリアの最後の半径 | `Config.ZoneEndRadius` | 18 |
| エリアの開始半径の下限・上限 | `Config.ZoneStartRadiusMin` / `Config.ZoneStartRadiusMax` | 50 / 120 |
| エリア外スタミナの減り・回復 | `Config.ZoneDrainPerSecond` / `Config.ZoneRegenPerSecond` | 12 / 25（最大100） |
| デッキの数 / 既定のデッキ | `Config.DeckSize` / `Config.DefaultDeck` | 3 / ダッシュ・シールド・ワープ |
| ボックスで得たアイテムの使用期限 | `Config.BoxExpireTime` | 15秒 |
| 通常の速さ / 鬼の速さ | `Config.NormalWalkSpeed` / `Config.TaggerWalkSpeed` | 16 / 20 |
| 鬼になった直後のタッチ無効時間 | `Config.TagCooldown` | 3 |
| タッチ判定の起点を鬼の正面に出す距離（スタッド） | `Config.TagReachForward` | 1.6 |
| 起点から相手のパーツまでの許容距離（スタッド） | `Config.TagTouchDistance` | 1.4 |
| アイテムの出現間隔 / 同時最大数 | `Config.ItemSpawnInterval` / `Config.MaxItemsOnMap` | 10 / 3 |
| アイテム使用キー（枠ごと） | `Config.ItemSlotKeys`（表示名は `Config.ItemSlotKeyLabels`） | 1枠目 E / X、2枠目 Q / Y |
| 通常の所持枠 / ダブルアイテムの所持枠 | `Config.BaseItemSlots` / `Config.Monetization.DoubleItem.ItemSlots` | 1 / 2 |
| leaderstats の項目名 | `Config.LeaderstatNames` | 逃げ切り / 鬼タッチ / ランク / RP |
| 段位の境界 | `Config.RankTiers` | ブロンズ 0、シルバー 100、ゴールド 250、プラチナ 500、ダイヤ 850、マスター 1300 |
| RP の配点 | `Config.RankPoints` | 逃げ切り 20 / 1人捕まえる 6 / 全員捕まえた 14 / 捕まった 4 |
| 段位の DataStore 名 / 定期保存 | `Config.RankDataStoreName` / `Config.RankSaveInterval` | `RankV1` / 180秒 |

アイテムごとの数字は `Config.Items` の中にあります。

- `Config.Items.Dash.Duration` / `WalkSpeed`: ダッシュの時間と速さ（5秒 / 26）
- `Config.Items.Smoke.Duration`: 鬼の画面が白くなる時間（3秒）
- `Config.Items.Shield.Duration` / `GraceTime`: シールドが残る時間（10秒）と、防いだ直後の無敵時間（1.5秒）
- `Config.Items.Warp.HeightOffset`: ワープ先の高さ
- `Config.Items.Star.Duration`: スターのタッチ無効時間（4秒）
- `Config.Items.Banana.SlipTime` / `SlipSpeed` / `Duration`: すべる時間（1.2秒）と速さ、置いたバナナが消えるまでの時間（20秒）
- 各アイテムの `DisplayName`（表示名）、`Description`（説明文）、`Color`（色）、`SpawnWeight`（出やすさ。0 にするとそのアイテムは出なくなる）、`CanTaggerUse`（鬼が使えるか）

## 課金

3つの商品があります。設定はすべて `src/shared/Config.lua` の **`Config.Monetization`** の節にあります。

| 商品 | 種類 | 目安価格 | 効果 |
|---|---|---|---|
| アイテムボックス | Developer Product（消費型。何度でも買える） | 10 Robux | ランダムなバトルアイテムが1つ手に入る。枠がいっぱいなら、いちばん古いアイテムと入れ替える（画面にメッセージが出る） |
| ダブルアイテム | Game Pass（買い切り） | 99 Robux | 所持できるアイテムが1つ → 2つになる（2つ目は Q キー / 左側のボタン） |
| キラキラトレイル | Game Pass（買い切り） | 49 Robux | 走ると光の軌跡が出る。見た目だけで、速さや判定は変わらない |

### しくみ（どこで何が決まるか）

- **購入画面を出すのはクライアント**（`Shop.client.lua` の `PromptProductPurchase` / `PromptGamePassPurchase`）、**付与を決めるのはすべてサーバー**（`Monetization.lua`）です。
- アイテムボックスは `MarketplaceService.ProcessReceipt` でレシートを受け取り、`ProductId` が `Config.Monetization.ItemBox.ProductId` と一致するときだけ付与して `PurchaseGranted` を返します。
  - 処理済みの `PurchaseId` をサーバーのメモリに記録し、同じレシートが再送されても二重に付与しません（記録はそのサーバーにいる間だけ。DataStore は使っていません）。
  - ショップではラウンドに参加している間だけ買えます。万一ラウンド外にレシートが届いた場合（ラウンド終了と同時に購入が完了した、など）は「予約」として持っておき、次のラウンド開始時に渡します。
  - 鬼が買ったときは、鬼が使えるアイテム（ダッシュ・ワープ）の中から選びます。
- Game Pass は、参加時と購入完了時（`PromptGamePassPurchaseFinished`）に `UserOwnsGamePassAsync` で確認し、結果をサーバーの `GameState` に持ちます。購入直後から再参加なしで反映されます。
- ID が `0` の商品は、ショップで「準備中」と表示され、購入ボタンは押せません。

### 1. Creator Dashboard で商品を作る

先にゲームを Roblox に公開しておく必要があります（Studio の「ファイル」→「Roblox に公開」）。商品はゲーム（エクスペリエンス）ごとに作ります。
※ Creator Dashboard の画面や項目名は変わることがあります。見つからないときは Roblox の公式ドキュメント（Developer Products / Passes のページ）を確認してください。

1. https://create.roblox.com/dashboard/creations を開き、このゲームを選びます。
2. 左のメニューの **収益化（Monetization）** を開きます。
3. **Developer Product を1つ作る**: 「デベロッパー製品（Developer Products）」→「作成」
   - 名前: `アイテムボックス`
   - 説明: 例「ランダムなバトルアイテムが1つ手に入る」
   - 価格: **10 Robux**
   - アイコン画像は任意です。
4. **Game Pass を2つ作る**: 「パス（Passes）」→「パスを作成」
   - 1つ目 名前: `ダブルアイテム`、説明: 例「アイテムを2つまで持てる」
   - 2つ目 名前: `キラキラトレイル`、説明: 例「走ると光の軌跡が出る（見た目だけ）」
   - 作ったあと、各パスの「販売（Sales）」の設定で **販売中（Item for Sale）** をオンにし、価格を **ダブルアイテム 99 Robux**、**キラキラトレイル 49 Robux** にします（オンにしないと買えません）。

### 2. ID を調べて Config に書き込む

- **Developer Product の ID**: 収益化 → デベロッパー製品の一覧で、商品の「…」メニュー →「ID をコピー」（または商品の詳細画面に表示される数字）。
- **Game Pass の ID**: 収益化 → パスの一覧で、パスの「…」メニュー →「アセット ID をコピー」。パスのページの URL（`.../passes/1234567/...`）の数字も同じ ID です。

コピーした数字を `src/shared/Config.lua` の次の3か所（★印）に書き込みます。

```lua
Config.Monetization = {
	ItemBox = {
		ProductId = 0,   -- ★ アイテムボックス（Developer Product）の ID
		...
	DoubleItem = {
		PassId = 0,      -- ★ ダブルアイテム（Game Pass）の ID
		...
	SparkleTrail = {
		PassId = 0,      -- ★ キラキラトレイル（Game Pass）の ID
```

書き換えたら、ショップの「準備中」が「購入（R$ 価格）」に変わります。価格の表示は Roblox から自動で取ってくるので、Config の `PriceHint` は目安のメモです（画面には使いません）。

### 3. Studio での購入テストの注意点

- Studio のテストプレイ中の購入は**テスト購入**で、Robux は減りません。確認ダイアログにもテストである旨が出ます。
- **アイテムボックス**: テスト購入でも `ProcessReceipt` が呼ばれるので、付与・入れ替えのメッセージまで確認できます。ラウンド中に参加しているときだけ買えるので、「クライアントとサーバー」で2人以上にしてラウンドを始めてから試してください。
- **Game Pass**: Studio のテスト購入では `UserOwnsGamePassAsync` が `true` にならないことがあります。そのため購入完了（`wasPurchased = true`）を受け取ったときは、それを優先して反映しています（Output に警告が1行出ますが正常です）。テストを止めて再開すると「未所有」に戻ります。本当の所有確認（参加時の確認）は、公開したゲームで実際に購入して確かめてください。
- 商品は公開済みのゲームに紐づいています。別のゲームの ID を入れると購入画面が出ないか、エラーになります。
- 1人テスト（「プレイ」）でラウンドを待機したままなら、アイテムボックスは「ラウンド中のみ」と表示されて買えません。Game Pass は1人でも試せます。

## 注意

- 移動はクライアント側の物理で動くため、チート対策（速度の改ざん検知など）までは入れていません。タッチ判定・アイテムの所持と効果はサーバーで確定しています。
- 段位・逃げ切り・鬼タッチの累計は DataStore `RankV1` に保存します（[段位](#段位ランク)）。Studio では API アクセスをオンにしないと保存されません。読み込みが終わる前に抜けると、その直前の加算は保存されないことがあります。
- アイテムボックスの二重付与防止の記録と「予約」は、そのサーバーにいる間だけ保持します。予約中（ラウンド外に購入が完了した場合のみ）にゲームを抜けると、その分は失われます。

### スマホでの操作

ボタンの最小サイズ（52 px）、画面端からの余白（16 px）、画面下の操作用の空き（120 px）は
共有の寸法表 `src/shared/UILayout.lua` で管理しています。アイテムボタンは画面下中央にあり、
右上の段位パネルでタッチ回数・捕まった回数・ラウンド獲得RPを確認できます。

## 管理者画面

個人所有の体験では、所有者の UserId が `game.CreatorId` と一致すると自動で管理者になります。追加する場合は `src/shared/Config.lua` の `Config.AdminUserIds` に数値の UserId を入れてください。グループ所有の体験でも、この配列で管理者を指定します。管理者として入室し、画面右側の **管理** ボタンを押すと開きます。

| 区分 | できること |
| --- | --- |
| プレイヤー | 入室中の人間の名前・段位・RP・参加状況を確認。選択した人をキック、BAN、試合中に鬼に変更、自分のところに呼ぶ、または相手のところへ移動。BAN一覧から解除。 |
| お知らせ | 現在のサーバーにいる全員に約3秒間表示。入力文には Roblox のテキストフィルターが適用されます。 |
| 進行 | 待ち時間を省いてラウンドを開始（生存している人間が1人以上必要）、試合を終了、次のマップへ移動、ボット補充を切り替え。マップ移動は試合中なら終了処理後に行い、ボット設定は次の補充時に反映されます。 |
| 付与と情報 | プレイヤー欄で選んだ人にアイテムを1個または RP（1〜1,000,000の整数）を付与。マップ、フェーズ、参加人数、稼働時間、直近20件の操作履歴を確認。アイテムは試合中の参加者に即時付与し、待機中や観戦中は次に参加する試合で渡します。マップ固有アイテムの使用条件は通常と同じです。 |

BAN の理由は DataStore **`AdminBansV1`** に UserId をキーとして保存されます。解除するには **プレイヤー → BAN一覧を取得** で UserId を選び、**BAN解除** を押してください。必要に応じて **次のBAN一覧** で次のページに進めます。入室時の読み込みに失敗した場合は警告を出して入室を続行します。保存に失敗した場合はパネルに失敗が表示されます。Studio で BAN の保存・解除を確認するには、公開済みのテスト用の体験で Studio からの API サービスへのアクセスを有効にしてください。
