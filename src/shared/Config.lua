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
Config.NormalJumpHeight = 7.2    -- 通常のジャンプの高さ

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
-- 0 になると中央へ強制送還される。送還は ZoneMaxReturns 回まで。その次で脱落（観戦）。
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
Config.ZoneMaxReturns = 2          -- 強制送還できる回数。これを使い切った次は脱落
Config.ZoneReturnRadius = 12       -- 強制送還で戻す場所（中央からこの半径の中）
Config.SpectatorPosition = Vector3.new(0, 153, 0) -- 脱落した人を置く観戦席（マップの上空）

---------------------------------------------------------------------
-- デッキ構築
-- ロビーで、持っているアイテムの中から DeckSize 個を選んでデッキにする（試合中は変えられない）。
-- フィールドのボックスを拾うと、自分のデッキの中からランダムで1つ手に入る。
---------------------------------------------------------------------
Config.DeckSize = 4                                        -- デッキに入れられる数
Config.StarterItems = { "Dash", "Banana", "Warp", "Shield" } -- 最初から持っているアイテム
Config.DefaultDeck = { "Dash", "Banana", "Warp", "Shield" }  -- 選んでいない人のデッキ

---------------------------------------------------------------------
-- フィールドのアイテムボックス
---------------------------------------------------------------------
Config.BoxExpireTime = 0   -- ボックスで手に入れたアイテムの使用期限（秒）。0 は期限なし（ためて後で使える）

---------------------------------------------------------------------
-- アイテム使用の操作
---------------------------------------------------------------------
-- 所持はリスト形式。枠ごとに使うキーが決まっている。
--   1枠目: キーボードの E / ゲームパッドの X
--   2枠目: Q / Y   3枠目: R / B   4枠目: F / DPadUp（ダブルアイテム所有者のみ）
Config.ItemSlotKeys = {
	{ Enum.KeyCode.E, Enum.KeyCode.ButtonX },
	{ Enum.KeyCode.Q, Enum.KeyCode.ButtonY },
	{ Enum.KeyCode.R, Enum.KeyCode.ButtonB },
	{ Enum.KeyCode.F, Enum.KeyCode.DPadUp },
}
Config.ItemSlotKeyLabels = { "E", "Q", "R", "F" } -- 画面のボタンやメッセージに出すキー名
Config.BaseItemSlots = 3         -- 通常の所持枠の数（ためて終盤に使えるよう 3 枠）
Config.UseItemCooldown = 0.5     -- 連打防止（サーバー側でもチェック）

---------------------------------------------------------------------
-- leaderstats の項目名
---------------------------------------------------------------------
Config.LeaderstatNames = {
	Survived = "逃げ切り",        -- 鬼にならずにラウンドを終えた回数
	Tagged = "鬼回数",            -- この試合で鬼にタッチされて鬼になった回数
	Returns = "送還",             -- この試合で強制送還された回数
	Coins = "コイン",             -- ロビーで表示する所持コイン
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
		Tier = "Ume",
		Price = 0,
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
		Tier = "Take",
		Price = 400,
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
		Tier = "Take",
		Price = 0,
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
		Tier = "Take",
		Price = 0,
		DisplayName = "ワープ",
		Description = "ランダムな出現ポイントへ瞬間移動",
		Color = Color3.fromRGB(190, 90, 255),
		SpawnWeight = 1,
		CanTaggerUse = true,
		HeightOffset = 3,        -- 出現ポイントの何スタッド上に移動するか
	},
	Star = {
		Id = "Star",
		Tier = "Matsu",
		Price = 900,
		DisplayName = "スター",
		Description = "4秒間、鬼にタッチされなくなる",
		Color = Color3.fromRGB(255, 180, 0),
		SpawnWeight = 1,
		CanTaggerUse = false,    -- 鬼には意味がないので使えない
		Duration = 4,            -- タッチ無効の秒数
	},
	Banana = {
		Id = "Banana",
		Tier = "Ume",
		Price = 0,
		DisplayName = "バナナ",
		Description = "足元に置く。踏んだ人がすべってしまう",
		Color = Color3.fromRGB(255, 235, 130),
		SpawnWeight = 1,
		CanTaggerUse = true,
		Duration = 20,           -- 置いたバナナが消えるまでの秒数
		SlipTime = 1.2,          -- 踏んだ人がすべる秒数
		SlipSpeed = 26,          -- すべる速さ
	},
	-----------------------------------------------------------------
	-- ここから追加アイテム（梅 = 150 / 竹 = 400 / 松 = 900 コイン）
	-----------------------------------------------------------------
	HighJump = {
		Id = "HighJump",
		Tier = "Ume",
		Price = 150,
		DisplayName = "ハイジャンプ",
		Description = "6秒間、ジャンプがとても高くなる（コンテナの上へ逃げられる）",
		Color = Color3.fromRGB(120, 255, 160),
		SpawnWeight = 1,
		CanTaggerUse = true,
		Duration = 6,
		JumpHeight = 17,         -- 効果中の JumpHeight（通常は約7.2）
	},
	Decoy = {
		Id = "Decoy",
		Tier = "Ume",
		Price = 150,
		DisplayName = "ダミー人形",
		Description = "自分そっくりの人形をその場に置く（10秒）。鬼の目をごまかせ",
		Color = Color3.fromRGB(230, 200, 170),
		SpawnWeight = 1,
		CanTaggerUse = false,
		Duration = 10,
	},
	Flash = {
		Id = "Flash",
		Tier = "Ume",
		Price = 150,
		DisplayName = "フラッシュ",
		Description = "近く（30スタッド以内）の鬼の画面を1.5秒まっ白にする",
		Color = Color3.fromRGB(255, 255, 210),
		SpawnWeight = 1,
		CanTaggerUse = false,
		Range = 30,
		Duration = 1.5,
		FadeOutTime = 0.3,
	},
	Sneak = {
		Id = "Sneak",
		Tier = "Ume",
		Price = 150,
		DisplayName = "しのび足",
		Description = "8秒間、体がほぼ透明になり名前も消える",
		Color = Color3.fromRGB(150, 150, 190),
		SpawnWeight = 1,
		CanTaggerUse = true,
		Duration = 8,
		Transparency = 0.85,
	},
	Glue = {
		Id = "Glue",
		Tier = "Take",
		Price = 400,
		DisplayName = "ねばねば罠",
		Description = "足元に罠を置く。踏んだ鬼は3秒間とても遅くなる（25秒で消える）",
		Color = Color3.fromRGB(170, 230, 60),
		SpawnWeight = 1,
		CanTaggerUse = false,
		Duration = 25,           -- 罠が残る秒数
		SlowTime = 3,            -- 踏んだ鬼が遅くなる秒数
		SlowSpeed = 7,           -- 遅くなったときの WalkSpeed
	},
	AirBurst = {
		Id = "AirBurst",
		Tier = "Take",
		Price = 400,
		DisplayName = "エアバースト",
		Description = "まわり（14スタッド以内）の全員を吹き飛ばす",
		Color = Color3.fromRGB(140, 220, 255),
		SpawnWeight = 1,
		CanTaggerUse = true,
		Range = 14,
		PushSpeed = 70,          -- 横向きの勢い
		LiftSpeed = 35,          -- 上向きの勢い
	},
	ZoneGuard = {
		Id = "ZoneGuard",
		Tier = "Take",
		Price = 400,
		DisplayName = "エリアガード",
		Description = "12秒間、エリアの外にいてもスタミナが減らない（外のボックスを取りに行ける）",
		Color = Color3.fromRGB(255, 120, 220),
		SpawnWeight = 1,
		CanTaggerUse = true,
		Duration = 12,
	},
	Radar = {
		Id = "Radar",
		Tier = "Take",
		Price = 400,
		DisplayName = "レーダー",
		Description = "8秒間、壁ごしに相手が光って見える（逃げる人には鬼、鬼には逃げる人）",
		Color = Color3.fromRGB(60, 255, 230),
		SpawnWeight = 1,
		CanTaggerUse = true,
		Duration = 8,
	},
	TimeStop = {
		Id = "TimeStop",
		Tier = "Matsu",
		Price = 900,
		DisplayName = "タイムストップ",
		Description = "鬼を2.5秒間その場に止める",
		Color = Color3.fromRGB(255, 215, 80),
		SpawnWeight = 1,
		CanTaggerUse = false,
		Duration = 2.5,
	},
	SecondChance = {
		Id = "SecondChance",
		Tier = "Matsu",
		Price = 900,
		DisplayName = "セカンドチャンス",
		Description = "強制送還の回数を1回分なかったことにする",
		Color = Color3.fromRGB(255, 90, 90),
		SpawnWeight = 1,
		CanTaggerUse = true,
	},
}

-- アイテムの並び順（ショップやデッキ画面の表示順）
Config.ItemOrder = {
	"Dash", "Banana", "HighJump", "Decoy", "Flash", "Sneak",
	"Warp", "Shield", "Smoke", "Glue", "AirBurst", "ZoneGuard", "Radar",
	"Star", "TimeStop", "SecondChance",
}

-- ランク（松竹梅）の表示
Config.Tiers = {
	Ume = { Name = "梅", Color = Color3.fromRGB(120, 200, 120) },
	Take = { Name = "竹", Color = Color3.fromRGB(80, 160, 230) },
	Matsu = { Name = "松", Color = Color3.fromRGB(240, 180, 40) },
}

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
		Description = "アイテムを4つまで持てる（4つ目は F キー / 4枠目のボタンで使う）",
		PriceHint = 99,
		ItemSlots = 4,           -- 所有者の所持枠の数（通常 3 → 4）
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

---------------------------------------------------------------------
-- 順位とコイン
--   順位: ①最後まで残り、最後の鬼ではない人を「鬼になった回数」が少ない順
--         ②最後の鬼（負け）  ③脱落した人（あとまで残った人ほど上）
--   一度もタッチされずに逃げ切った人が「優勝」で、いちばん多くもらえる。
---------------------------------------------------------------------
Config.CoinRewards = {
	Champion = 120,       -- 一度もタッチされずに逃げ切った
	Survivor = 70,        -- 逃げ切った（タッチされた回数で減る）
	PerTagPenalty = 15,   -- タッチされた1回ごとに減る枚数
	SurvivorMin = 25,     -- 逃げ切った人の最低枚数
	FinalTagger = 10,     -- 最後に鬼だった
	Eliminated = 5,       -- エリア外で脱落した
}

---------------------------------------------------------------------
-- ロビーと部屋
---------------------------------------------------------------------
Config.LobbyPlaceId = 126711017852469 -- ロビー（スタートプレース）
Config.MatchPlaceId = 133704424283393 -- 試合用プレース
Config.QuickMaxPlayers = 8            -- 自動で始まる部屋の最大人数
Config.QuickCountdown = 12            -- 2人そろってから出発までの秒数
Config.QuickFullCountdown = 4         -- 満員になったら出発までの秒数
Config.QuickPadRadius = 9             -- 「すぐ遊ぶ」パッドの半径（この中に立つと参加）
Config.MatchArrivalTimeout = 25       -- 試合サーバーで全員の到着を待つ最大秒数
Config.FriendRoomCodeLength = 4       -- 友達部屋の合言葉の桁数
Config.FriendRoomLifetime = 3 * 60 * 60 -- 合言葉が有効な秒数
Config.FriendMaxPlayers = 12          -- 友達部屋の最大人数

---------------------------------------------------------------------
-- BGM（Creator Store の正規ライセンス曲）
---------------------------------------------------------------------
Config.Music = {
	Lobby = "rbxassetid://99572829037282",   -- Cheerful Upbeat Chase 1
	Match = "rbxassetid://119305326515198",  -- Cheerful Upbeat Chase 2
	Final = "rbxassetid://9045941477",       -- Mission Danger - Underscore（残り30秒から）
	FinalTime = 30,                          -- 残り何秒で終盤の曲に切り替えるか
	Volume = 0.35,
}

-- ランクの表示名を返す（"梅" など）
function Config.GetTierName(tier)
	local info = Config.Tiers[tier]
	return info and info.Name or ""
end

return Config
