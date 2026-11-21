# 依頼：渋谷風の街マップ（コード生成）を追加する

対象リポジトリ：このフォルダ（roblox-tag-battle）。既存のゲーム本体（鬼ごっこ）には手を入れず、
マップをコードで生成する仕組みを足す。完了条件は末尾の「検証」まで全部通ること。

## 前提（確認済みの事実）

- `ItemManager.GetSpawnPoints()` は試合開始時に `Workspace.ItemSpawns` フォルダ内の BasePart を
  都度読む（初期化時のスナップショットではない）。ZoneManager も同じ関数を使う。
- したがって、サーバー起動時に Workspace へマップと ItemSpawns を作れば、そのまま連動する。
- Main.server.lua の初期化順は Leaderstats → ItemManager → DeckManager → RoundManager → Monetization → Run()。

## 作るもの

### 1. 新規ファイル `src/server/MapBuilder.lua`

モジュール（ModuleScript想定。既存モジュールと同じ書き方・日本語コメント）として、
`MapBuilder.Build()` を呼ぶと Workspace にマップ一式を生成する。

冪等性：`Workspace.Map` と `Workspace.ItemSpawns` が既にあれば削除してから作り直す。

#### 全体レイアウト（スタイライズした渋谷風。写実再現は狙わない）

- 舞台はおよそ 220×220 スタッドの正方形。中心がスクランブル交差点。
- 地面：アスファルト色の大きなベース1枚（Anchored、CanCollide true）。
- 道路：中心で十字に交わる2本の道路（幅 約36）。濃いアスファルト色。
  交差点の4方向すべてに横断歩道（白い細長い Part を並べたゼブラ模様）。
  道路には中央線（黄色〜白の細い Part）を引く。
- 歩道： city ブロックの周囲に、少し高くした明るい灰色の歩道。
- 建物：交差点を取り囲むブロックに、箱型のビルを並べる。
  高さ 20〜70 でばらつかせ、色は落ち着いた色調で数色。
  窓の表現は薄い Part の帯や明るい色の面で簡略化してよい（Part 数を抑えること）。
  低い建物2〜3棟は屋上に登れるようにする（階段かスロープを付ける。鬼ごっこの動線のため）。
- ランドマーク：交差点の一角に大きなスクリーンのあるビル1棟。
  スクリーンは Neon 素材の明るい Part とし、SurfaceGui の TextLabel で「SHIBUYA」と表示する。
- 小物（鬼ごっこの障害物・隠れ場所）：植え込み、自販機風の箱（赤・青）、バス停の屋根、
  信号機の柱（交差点の角）、街灯、バリケード、木（幹＝円柱、葉＝球）のある小さな広場。
- 外周：舞台の外に出られないよう、透明な壁（Transparency 1、CanCollide true、高さ約30）を4辺に。

#### 配置データの持ち方

- 建物や小物は、位置・大きさ・高さ・色を並べたテーブルで定義し、ループで生成する。
- 乱数は使わないか、使うなら固定シード。毎回同じマップになること。

#### ItemSpawns

- `Workspace.ItemSpawns` フォルダを作り、出現ポイントを **12点** 置く。
  交差点周辺、路地、屋上2点、広場、駅前風の広場などに分散させる。
- 各ポイント：Part、Size は 2×1×2、Transparency 1、CanCollide false、Anchored true、
  Name は Spawn1〜Spawn12。置く面から約3スタッド上に中心が来るようにする。

#### プレイヤーのスポーン

- 交差点近くの広場に SpawnLocation を1つ置く（Neutral、Anchored、大きさ約 12×1×12）。
  見た目は薄く色を付け、Decal は不要。

#### Part 数の上限

- マップ全体の BasePart 数は **700以下** を目安にする（窓の帯の付けすぎに注意）。

### 2. `src/server/Main.server.lua` の変更（最小限）

- MapBuilder を require し、他の Init より前（ファイル先頭の初期化ブロック内）で
  `MapBuilder.Build()` を1回呼ぶ。コメントで理由（ItemSpawns を試合開始前に用意するため）を書く。
- それ以外の既存行は変更しない。

### 3. テスト追加（tests/）

既存の mockenv を使って MapBuilder を読み、Build() 実行後に次を検証するテストを足す。

- Workspace.ItemSpawns が存在し、BasePart が12個ある
- Workspace.Map が存在する
- 出現ポイントがすべて舞台の範囲内（|x| <= 115 かつ |z| <= 115）にある
- 横断歩道の白い Part が存在する（色で数えて 20 個以上など、実装に合った現実的な条件でよい）
- BasePart の総数が 700 以下

既存テストの流儀（build_tests.py / run_tests.lua の構成）に合わせること。
既存の40テストを壊さない。

### 4. README.md に追記

- マップはコード生成であること（MapBuilder.Build() が起動時に生成）
- Studio で開いただけではマップは見えず、Play でサーバーが起動すると生成されること
- マップを無効化するには Main.server.lua の Build() 呼び出しを外すこと

## やらないこと

- ゲーム本体のルール・アイテム・課金の変更
- Lighting の変更
- Config.lua の変更（ItemSpawnFolderName は既存の値を参照するだけ）

## 検証（完了条件）

1. 変更した全 .lua ファイルが luau-compile で構文エラーなし
2. テスト全件パス（既存40件＋追加分）
3. `rojo build` が成功する
4. 作業報告として、生成される Part 数の実測と、屋上に登る手段を付けた建物の数を報告すること
