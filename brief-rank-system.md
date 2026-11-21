# 依頼：段位（ランク）システムを追加する

対象リポジトリ：このフォルダ（roblox-tag-battle）。鬼ごっこに、遊ぶほど上がる段位の仕組みを足す。
完了条件は末尾の「検証」まで全部通ること。

## 前提（確認済みの事実）

- 現在の leaderstats は「逃げ切り（Survived）」「鬼タッチ（Tagged）」の2項目で、その場限り（保存なし）。
- DataStore は未使用。今回が初の保存基盤になる。
- Main.server.lua の初期化順は MapBuilder → Leaderstats → ItemManager → DeckManager → RoundManager → Monetization → Run()。

## 設計（この通りに作る）

### 段位とランクポイント（RP）

- RPは**減らない累積式**。試合結果で加算され、累計RPで段位が決まる。
- 段位表（Config.lua に `Config.RankTiers` として定義。下限RPと名前と色）：

  | 段位 | 累計RP |
  |---|---|
  | ブロンズ | 0 |
  | シルバー | 100 |
  | ゴールド | 250 |
  | プラチナ | 500 |
  | ダイヤ | 850 |
  | マスター | 1300 |

  色は段位らしい色を Color3 で付ける（ブロンズ＝銅色、シルバー＝銀色、ゴールド＝金色、
  プラチナ＝水色寄りの白、ダイヤ＝明るい水色、マスター＝紫）。

- RPの配点（Config.lua に `Config.RankPoints` として定義）：
  - 逃げ切り（最後まで捕まらなかった）：+20
  - 鬼が1人捕まえるごと：+6
  - 鬼が全員捕まえた：追加で +14
  - 捕まった：+4（参加分）

### 保存（DataStore）

- 新規モジュール `src/server/RankManager.lua` が担う。
- DataStore 名は `RankV1`、キーは `tostring(player.UserId)`。
  保存内容は `{ RP = 数値, Survived = 数値, Tagged = 数値 }`。
  既存の leaderstats 2項目も累計として一緒に保存・復元する（次回来たとき続きから表示される）。
- 読み込みは PlayerAdded 時、保存は PlayerRemoving 時と BindToClose、
  それと 180 秒ごとの定期保存（全プレイヤー）。すべて pcall で囲み、
  失敗してもゲームは止めない（warn を出す）。読み込み失敗時は 0 から始める。
- Studio では API アクセスを有効にしないと DataStore が使えない。その前提は README に明記する
  （コード側で特別な判定はしない）。

### 表示

- leaderstats に2項目を追加する：
  - 「ランク」：StringValue、段位名（例「ゴールド」）
  - 「RP」：IntValue、累計RP
  Leaderstats.lua の STAT_KEYS の仕組みにそのまま乗せるか、RankManager が値を同期するかは、
  既存構造に合う方を選んでよい。ただし表示名は Config.LeaderstatNames に追加して一元管理する。
- HUD（クライアント）：自分のランクとRPと「次の段位まであと◯RP」を1行で表示する。
  既存の HUD.client.lua の流儀に合わせ、leaderstats の値を読んで表示する（新しい Remote は使わない）。
- 昇格の通知：段位が上がった瞬間だけ、そのプレイヤーに知らせる。
  Remotes.lua に `RankUp` RemoteEvent を追加し、クライアントは MatchUI か HUD で
  「ランクアップ！ ◯◯に昇格」のような短い表示を数秒出す。文言は日本語で簡潔に。

### RPの加算タイミング

- RoundManager の勝敗確定処理に接続する。既存の `Leaderstats.Increment` が呼ばれている箇所が目安。
- 加算は RankManager.Award(player, amount) のような入口を1つ作り、そこで
  累計RP更新・leaderstats 同期・昇格判定（上がったら RankUp を FireClient）まで行う。
- 鬼の「1人捕まえるごと +6」は、タッチが確定した処理の箇所で加算する。
  全員捕まえた追加 +14 は勝敗確定時に判定する。

## やらないこと

- 順位表（ランキング表示）は今回作らない。
- 課金まわり（Monetization）の変更。
- RPが減る仕組み（降格）は入れない。

## テスト追加（tests/）

- mockenv に DataStoreService の最小モックを足す
  （GetDataStore がメモリ上の表を返し、GetAsync/SetAsync/UpdateAsync が動く）。
- 次を検証する：
  - 段位判定の境界（RP 99→ブロンズ、100→シルバー、250→ゴールド、1300→マスター など）
  - Award で累計が増え、境界を越えると段位が上がり、RankUp が1回だけ飛ぶ
  - 保存して読み直すと RP と Survived / Tagged が復元される
  - DataStore が失敗を返すモックでも、読み込みが 0 始まりでゲームが止まらない
- 既存の58テストを壊さない。

## README 追記

- 段位表とRP配点
- 保存の仕様（DataStore 名、保存タイミング）
- Studio で試すには Game Settings → Security →「Enable Studio Access to API Services」を
  オンにする必要があること

## 検証（完了条件）

1. 変更した全 .lua ファイルが /tmp/luau-compile で構文エラーなし
2. テスト全件パス（既存58件＋追加分）。実行は `python3 tests/build_tests.py` のあと `/tmp/luau tests/run_tests.lua`
3. `/tmp/rojo build` が成功する
4. 報告に、追加したファイルと変更したファイルの一覧、テスト件数、想定の落とし穴
   （DataStore の待ち時間や Studio の API アクセスなど）を書くこと
