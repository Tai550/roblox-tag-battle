-- Config: ゲームの数字（時間・速度・アイテム定義）をまとめた設定モジュール
-- ここだけを書き換えれば、ゲームバランスを調整できるようにしています。
-- 配置先: ReplicatedStorage.Shared.Config （サーバーとクライアントの両方から読む）

local Config = {}

---------------------------------------------------------------------
-- ラウンド進行
---------------------------------------------------------------------
Config.MinPlayers = 2            -- ラウンド開始に必要な最低人数
Config.IntermissionTime = 15     -- 待機（インターミッション）の秒数
Config.ResultsTime = 6           -- 結果表示の秒数

-- 試合時間はインターミッション中の投票で決める（同数・無投票なら DefaultDuration）
Config.MatchDurations = { 60, 180, 300 } -- 選べる試合時間（秒）: 1分・3分・5分
Config.DefaultDuration = 180     -- 投票が割れたとき・無投票のときの試合時間（秒）

---------------------------------------------------------------------
-- 移動速度
---------------------------------------------------------------------
Config.NormalWalkSpeed = 16      -- 逃げる人・観戦中の人の WalkSpeed
Config.TaggerWalkSpeed = 20      -- 鬼の WalkSpeed

---------------------------------------------------------------------
-- タッチ判定（サーバー側で距離を測って判定する）
---------------------------------------------------------------------
Config.TagCooldown = 3           -- 鬼になった直後、タッチが無効になる秒数
Config.TagDistance = 5           -- この距離（スタッド）以内に近づいたら「タッチ」
Config.TagCheckInterval = 0.1    -- タッチ判定の間隔（秒）

---------------------------------------------------------------------
-- アイテム出現
---------------------------------------------------------------------
Config.ItemSpawnInterval = 10    -- 何秒ごとにアイテムを1つ出現させるか（ボックスは BoxSpawnInterval を使う）
Config.MaxItemsOnMap = 3         -- マップ上に同時に置けるアイテムの最大数（ボックスは BoxMaxOnMap を使う）
Config.BoxSpawnInterval = 8      -- 何秒ごとにボックスを1つ出現させるか
Config.BoxMaxOnMap = 4           -- マップ上に同時に置けるボックスの最大数
Config.ItemSpawnFolderName = "ItemSpawns" -- Workspace 内の出現ポイント用フォルダ名
Config.ItemHeightOffset = 3      -- 出現ポイントの何スタッド上にアイテムを浮かせるか

-- ItemSpawns フォルダがない（または中に Part がない）ときの代わりの出現位置
Config.FallbackSpawnCenter = Vector3.new(0, 3, 0)
Config.FallbackSpawnOffsets = {
	Vector3.new(0, 0, 0),
	Vector3.new(10, 0, 0),
	Vector3.new(-10, 0, 0),
	Vector3.new(0, 0, 10),
	Vector3.new(0, 0, -10),
}

---------------------------------------------------------------------
-- 縮小エリア（ゾーン）
-- ラウンド中、エリアは円形に縮み続ける。外に出続けると専用スタミナが減り、
-- 0 になるとエリアの中へ戻される（脱落はしない）。
---------------------------------------------------------------------
Config.ZoneEndRadius = 18          -- 縮小が止まる最後の半径
Config.ZoneStartRadiusMin = 50     -- 開始半径の下限
Config.ZoneStartRadiusMax = 120    -- 開始半径の上限
Config.ZoneStartRadiusPadding = 15 -- 開始半径 = 出現ポイントの最大距離 + この値
Config.ZoneFallbackRadius = 60     -- 予備ポイントだけのマップでの開始半径
Config.ZoneShrinkEndRatio = 0.8    -- 試合時間のこの割合が過ぎるまで縮み続ける
Config.ZoneStaminaMax = 100        -- エリア外スタミナの最大値
Config.ZoneDrainPerSecond = 12     -- エリア外で1秒に減るスタミナ
Config.ZoneRegenPerSecond = 25     -- エリア内で1秒に回復するスタミナ
Config.ZoneCheckInterval = 0.25    -- エリア内外の判定間隔（秒）
Config.ZoneWallHeight = 60         -- 壁の高さ
Config.ZoneWallColor = Color3.fromRGB(255, 90, 200) -- 壁の色
Config.ZoneWallTransparency = 0.5  -- 壁の透明度
Config.ZoneWallSegments = 64       -- 壁を何枚のパネルで円にするか（多いほどなめらか）
Config.RespawnRayHeight = 60       -- リスポーン時、どの高さから足場を探すか

---------------------------------------------------------------------
-- デッキ構築
-- 全アイテムの中から3つ選んでデッキにする。フィールドのボックスを拾うと、
-- 自分のデッキの中からランダムで1つ手に入る。
---------------------------------------------------------------------
Config.DeckSize = 3                              -- デッキに入れられる数
Config.DefaultDeck = { "Dash", "Shield", "Warp" } -- 選んでいない人のデッキ

---------------------------------------------------------------------
-- フィールドのアイテムボックス
---------------------------------------------------------------------
Config.BoxExpireTime = 15  -- ボックスで手に入れたアイテムの使用期限（秒）。過ぎると消える

---------------------------------------------------------------------
-- アイテム使用の操作
---------------------------------------------------------------------
-- 所持はリスト形式。枠ごとに使うキーが決まっている。
--   1枠目: キーボードの E / ゲームパッドの X
--   2枠目: キーボードの Q / ゲームパッドの Y（ダブルアイテム所有者のみ）
Config.ItemSlotKeys = {
	{ Enum.KeyCode.E, Enum.KeyCode.ButtonX },
	{ Enum.KeyCode.Q, Enum.KeyCode.ButtonY },
}
Config.ItemSlotKeyLabels = { "E", "Q" } -- 画面のボタンやメッセージに出すキー名
Config.BaseItemSlots = 1         -- 通常の所持枠の数
Config.UseItemCooldown = 0.5     -- 連打防止（サーバー側でもチェック）

---------------------------------------------------------------------
-- leaderstats の項目名
---------------------------------------------------------------------
Config.LeaderstatNames = {
	Survived = "逃げ切り",        -- 鬼にならずにラウンドを終えた回数
	Tagged = "鬼タッチ",          -- 鬼にタッチされて鬼になった回数
}

---------------------------------------------------------------------
-- バトルアイテム定義
--   Id           : 内部で使う名前（Items のキーと同じにする）
--   DisplayName  : 画面に出す名前
--   Description  : 拾ったときに出す説明
--   Color        : マップ上のアイテムの色
--   SpawnWeight  : 出現しやすさ（大きいほど出やすい。0 で出なくなる）
--   CanTaggerUse : 鬼が使えるかどうか
---------------------------------------------------------------------
Config.Items = {
	Dash = {
		Id = "Dash",
		DisplayName = "ダッシュ",
		Description = "5秒間、足がとても速くなる",
		Color = Color3.fromRGB(255, 200, 40),
		SpawnWeight = 1,
		CanTaggerUse = true,
		Duration = 5,            -- 効果時間（秒）
		WalkSpeed = 26,          -- 効果中の WalkSpeed
	},
	Smoke = {
		Id = "Smoke",
		DisplayName = "スモーク",
		Description = "鬼の画面を3秒間まっ白にする",
		Color = Color3.fromRGB(200, 200, 200),
		SpawnWeight = 1,
		CanTaggerUse = false,    -- 鬼が使うと自分に効いてしまうので不可
		Duration = 3,            -- 画面が真っ白になる秒数
		FadeOutTime = 0.5,       -- 白い画面が消えるまでのフェード秒数
	},
	Shield = {
		Id = "Shield",
		DisplayName = "シールド",
		Description = "1回だけ鬼のタッチを防ぐ（10秒で消える）",
		Color = Color3.fromRGB(80, 170, 255),
		SpawnWeight = 1,
		CanTaggerUse = false,    -- 鬼には使えない
		Duration = 10,           -- シールドが残る秒数
		GraceTime = 1.5,         -- タッチを防いだ直後、続けてタッチされない秒数
	},
	Warp = {
		Id = "Warp",
		DisplayName = "ワープ",
		Description = "ランダムな出現ポイントへ瞬間移動",
		Color = Color3.fromRGB(190, 90, 255),
		SpawnWeight = 1,
		CanTaggerUse = true,
		HeightOffset = 3,        -- 出現ポイントの何スタッド上に移動するか
	},
	Star = {
		Id = "Star",
		DisplayName = "スター",
		Description = "4秒間、鬼にタッチされなくなる",
		Color = Color3.fromRGB(255, 180, 0),
		SpawnWeight = 1,
		CanTaggerUse = false,    -- 鬼には意味がないので使えない
		Duration = 4,            -- タッチ無効の秒数
	},
	Banana = {
		Id = "Banana",
		DisplayName = "バナナ",
		Description = "足元に置く。踏んだ人がすべってしまう",
		Color = Color3.fromRGB(255, 235, 130),
		SpawnWeight = 1,
		CanTaggerUse = true,
		Duration = 20,           -- 置いたバナナが消えるまでの秒数
		SlipTime = 1.2,          -- 踏んだ人がすべる秒数
		SlipSpeed = 26,          -- すべる速さ
	},
}

-- アイテムの並び順（抽選や表示で使う）
Config.ItemOrder = { "Dash", "Smoke", "Shield", "Warp", "Star", "Banana" }

function Config.GetItem(itemId)
	if itemId == nil then
		return nil
	end
	return Config.Items[itemId]
end

-- 枠番号からキー名を返す（"E" / "Q"）
function Config.GetSlotKeyLabel(slot)
	return Config.ItemSlotKeyLabels[slot] or tostring(slot)
end

---------------------------------------------------------------------
-- 課金（Developer Product / Game Pass）
--   ★ 商品を Creator Dashboard で作ったら、ここの 0 を本物の ID に書き換える。
--   ID が 0 の商品は「準備中」扱いになり、ショップで購入ボタンが押せない。
---------------------------------------------------------------------
Config.Monetization = {
	-- アイテムボックス（Developer Product・消費型）: ランダムなバトルアイテムを1つ得る
	ItemBox = {
		ProductId = 0,           -- ★ Developer Product の ID
		DisplayName = "アイテムボックス",
		Description = "ランダムなバトルアイテムが1つ手に入る。枠がいっぱいなら、いちばん古いアイテムと入れ替え",
		PriceHint = 10,          -- 目安価格（Robux）。実際の価格は Creator Dashboard で決める
	},
	-- ダブルアイテム（Game Pass・買い切り）: 所持枠が 1 → 2 になる
	DoubleItem = {
		PassId = 0,              -- ★ Game Pass の ID
		DisplayName = "ダブルアイテム",
		Description = "アイテムを2つまで持てる（2つ目は Q キー / 2枠目のボタンで使う）",
		PriceHint = 99,
		ItemSlots = 2,           -- 所有者の所持枠の数
	},
	-- キラキラトレイル（Game Pass・買い切り）: 走ると光の軌跡が出る（見た目だけ）
	SparkleTrail = {
		PassId = 0,              -- ★ Game Pass の ID
		DisplayName = "キラキラトレイル",
		Description = "走ると光の軌跡が出る（見た目だけ。強さは変わらない）",
		PriceHint = 49,
		-- 見た目の設定
		Lifetime = 0.45,         -- 軌跡が残る秒数
		ColorStart = Color3.fromRGB(255, 240, 120),
		ColorEnd = Color3.fromRGB(120, 200, 255),
		TransparencyStart = 0.2,
		LightEmission = 1,
		AttachmentHeight = 0.9,  -- HumanoidRootPart の中心から上下に何スタッド離して Attachment を付けるか
	},
}

-- Game Pass の一覧（所有確認やショップ表示で使う）
Config.GamePassKeys = { "DoubleItem", "SparkleTrail" }

return Config
