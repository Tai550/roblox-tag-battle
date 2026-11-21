-- Config: ゲームの数字（時間・速度・アイテム定義）をまとめた設定モジュール
-- ここだけを書き換えれば、ゲームバランスを調整できるようにしています。
-- 配置先: ReplicatedStorage.Shared.Config （サーバーとクライアントの両方から読む）

local Config = {}

-- ブランドカラー（紫・黄・赤）。画面の色はここから取る
Config.BrandColors = {
	Primary = Color3.fromRGB(95, 25, 130),
	Surface = Color3.fromRGB(48, 13, 74),
	Secondary = Color3.fromRGB(140, 60, 190),
	Accent = Color3.fromRGB(255, 201, 6),
	Danger = Color3.fromRGB(225, 30, 55),
	White = Color3.fromRGB(255, 255, 255),
}
Config.RadarHighlightColor = Color3.fromRGB(60, 255, 230)

---------------------------------------------------------------------
-- ラウンド進行
---------------------------------------------------------------------
Config.AdminUserIds = {}         -- 追加の管理者の UserId（ゲームの所有者は自動で管理者）
Config.MinPlayers = 2            -- ラウンド開始に必要な最低人数（人間の数。ボットだけでは始まらない）
Config.BotFillTarget = 8         -- 人間がこれ未満なら、差分をボットで補う目標人数
Config.BotsEnabled = true        -- false にするとボット補充をしない
Config.IntermissionTime = 9      -- 待機（インターミッション）の秒数
Config.ResultsTime = 6           -- 結果表示の秒数

-- 試合時間はインターミッション中の投票で決める（同数・無投票なら DefaultDuration）
Config.MatchDurations = { 60, 180, 300 } -- 選べる試合時間（秒）: 1分・3分・5分
Config.DefaultDuration = 180     -- 投票が割れたとき・無投票のときの試合時間（秒）

-- マップの一覧（ローテーションの順番。開始前にこの中から投票できる）
Config.MatchMaps = {
	{ Id = "Arena", Name = "アリーナ", Gimmick = "None" },
	{ Id = "Shibuya", Name = "渋谷", Gimmick = "None" },
	{ Id = "Park", Name = "パーク", Gimmick = "None" },
	{ Id = "Cave", Name = "洞窟", Gimmick = "None", ExclusiveItemId = "Phase" },
	{ Id = "Ice", Name = "氷床", Gimmick = "Ice", ExclusiveItemId = "SpikeBoots" },
	{ Id = "Volt", Name = "痺れるダンジョン", VoteLabel = "痺れる", Gimmick = "Volt", ExclusiveItemId = "Insulate" },
	{ Id = "Sky", Name = "落下ダンジョン", VoteLabel = "落下", Gimmick = "None", ExclusiveItemId = "SafetyLine" },
}

---------------------------------------------------------------------
-- 移動速度
---------------------------------------------------------------------
Config.NormalWalkSpeed = 16      -- 逃げる人・観戦中の人の WalkSpeed
Config.IceSlideDecay = 0.55      -- 入力を離したときの減衰率（1/秒）。小さいほど長く滑る
Config.IceSlideSteering = 2.2    -- 入力方向への追従率（1/秒）。小さいほど曲がるときも滑る
Config.VoltStunTime = 1.2
Config.VoltRecoveryTime = 2
Config.FallEliminateY = 20      -- Sky の中央足場（Y=50）から30下

Config.TaggerWalkSpeed = 20      -- 鬼の WalkSpeed
Config.NormalJumpHeight = 7.2    -- 通常のジャンプの高さ

---------------------------------------------------------------------
-- タッチ判定（サーバー側で距離を測って判定する）
---------------------------------------------------------------------
Config.TagCooldown = 3           -- 鬼になった直後、タッチが無効になる秒数
Config.TagReachForward = 1.6     -- 鬼のルートから判定の起点を前に出す距離（スタッド）
Config.TagTouchDistance = 1.4    -- 起点から相手のパーツの表面までの許容距離（スタッド）
Config.TagBodyDistance = 3.5     -- 体が重なっている（ルート同士がこの距離以内）ならタッチ
Config.TagStackRadius = 2.5      -- 頭の上に乗っている／下にいる：水平でこの距離以内、高さの差 6 以内ならタッチ
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
Config.BoxGroundMaxHeight = 2.5  -- ボックスを出してよい地面の高さ（これより高い所＝建物の上には出さない）
Config.BoxSpawnTries = 20        -- 空いた地面を探す回数

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
Config.ZoneEndRadius = 25          -- 縮小が止まる最後の半径
Config.ZoneStartRadiusMin = 50     -- 開始半径の下限
Config.ZoneStartRadiusMax = 175    -- 開始半径の上限（フィールドの四隅まで入る大きさ）
Config.ZoneStartRadiusPadding = 80 -- 開始半径 = 出現ポイントの最大距離 + この値（最初はフィールド全体）
Config.ZoneFallbackRadius = 60     -- 予備ポイントだけのマップでの開始半径
Config.ZoneShrinkStartRatio = 0.3  -- 試合時間のこの割合までは縮まない（最初は広く遊べる）
Config.ZoneShrinkEndRatio = 0.85   -- 試合時間のこの割合で最後の半径まで縮みきる
Config.ZoneStaminaMax = 100        -- エリア外スタミナの最大値
Config.ZoneDrainPerSecond = 9      -- エリア外で1秒に減るスタミナ（0 まで約11秒）
Config.ZoneRegenPerSecond = 25     -- エリア内で1秒に回復するスタミナ
Config.ZoneCheckInterval = 0.25    -- エリア内外の判定間隔（秒）
Config.ZoneWallHeight = 60         -- 壁の高さ
Config.ZoneWallColor = Config.BrandColors.Danger -- 壁の色（ブランドの赤）
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
--   1枠目: E・1 / ゲームパッドの X
--   2枠目: Q・2 / Y   3枠目: R・3 / B   4枠目: F・4 / DPadUp（ダブルアイテム所有者のみ）
Config.ItemSlotKeys = {
	{ Enum.KeyCode.E, Enum.KeyCode.One, Enum.KeyCode.ButtonX },
	{ Enum.KeyCode.Q, Enum.KeyCode.Two, Enum.KeyCode.ButtonY },
	{ Enum.KeyCode.R, Enum.KeyCode.Three, Enum.KeyCode.ButtonB },
	{ Enum.KeyCode.F, Enum.KeyCode.Four, Enum.KeyCode.DPadUp },
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
	Rank = "ランク",              -- 段位名（例: ゴールド）。累計で保存
	RP = "RP",                    -- 累計ランクポイント
}

---------------------------------------------------------------------
-- 段位（ランク）
-- RP は減らない累積。試合結果で加算され、累計 RP で段位が決まる。
-- 段位は MinRP 以下の中で、いちばん高い MinRP の段。
---------------------------------------------------------------------
Config.RankDataStoreName = "RankV1" -- 保存先の DataStore 名
Config.RankSaveInterval = 180       -- 全員を定期保存する間隔（秒）

-- 下限 RP の昇順。色は画面の段位表示に使う。
Config.RankTiers = {
	{ MinRP = 0, Name = "ブロンズ", Color = Color3.fromRGB(184, 115, 51) },    -- 銅色
	{ MinRP = 100, Name = "シルバー", Color = Color3.fromRGB(192, 192, 192) }, -- 銀色
	{ MinRP = 250, Name = "ゴールド", Color = Color3.fromRGB(255, 214, 70) },  -- 金色
	{ MinRP = 500, Name = "プラチナ", Color = Color3.fromRGB(214, 240, 245) }, -- 水色寄りの白
	{ MinRP = 850, Name = "ダイヤ", Color = Color3.fromRGB(80, 220, 255) },    -- 明るい水色
	{ MinRP = 1300, Name = "マスター", Color = Color3.fromRGB(176, 96, 255) }, -- 紫
}

-- 1回のできごとでもらえる RP。減点はない。
Config.RankPoints = {
	Survived = 20,  -- 逃げ切り（最後まで捕まらなかった）
	Tag = 6,        -- 鬼が1人捕まえるごと
	TaggedAll = 14, -- 鬼が全員捕まえたとき、最後にタッチした鬼へ追加
	Caught = 4,     -- 捕まった（参加分）
}

---------------------------------------------------------------------
-- ボットの強さ（機械学習ではない）
-- ラウンド開始時、そのサーバーにいる人間の平均段位（RankTiers の位置。1 がブロンズ）で
-- 表を引くだけ。段位が高いほど歩く速さの倍率は上がり、経路の引き直し間隔は短くなる。
-- 速さ倍率は BotSpeedMultiplierCap で頭打ち（表の値が大きくても超えない）。
---------------------------------------------------------------------
Config.BotSpeedMultiplierCap = 1.15
Config.BotStrengthByTier = {
	{ SpeedMultiplier = 1.00, RepathInterval = 1.40 }, -- 1 ブロンズ
	{ SpeedMultiplier = 1.03, RepathInterval = 1.20 }, -- 2 シルバー
	{ SpeedMultiplier = 1.06, RepathInterval = 1.00 }, -- 3 ゴールド
	{ SpeedMultiplier = 1.09, RepathInterval = 0.80 }, -- 4 プラチナ
	{ SpeedMultiplier = 1.12, RepathInterval = 0.65 }, -- 5 ダイヤ
	{ SpeedMultiplier = 1.15, RepathInterval = 0.50 }, -- 6 マスター
}

-- ボットの判断に使う距離（スタッド）と時間（秒）
Config.BotItemSeekDistance = 40   -- この距離以内の宝箱を取りに行く
Config.BotItemSafeDistance = 30   -- 鬼がこれより近いときは宝箱を諦めて逃げる
Config.BotZoneEdgeRatio = 0.85    -- 半径のこの割合より外なら、内側へ戻る
Config.BotFleeDistance = 28       -- 鬼から離れるとき、この先を目標にする
Config.BotDashDistance = 45       -- 逃げ中、鬼がこの距離以内ならダッシュを使う
Config.BotShieldDistance = 18     -- 鬼がこの距離以内ならシールドを使う
Config.BotStarDistance = 18       -- 鬼がこの距離以内ならスターを使う
Config.BotWarpDistance = 14       -- 相手がこの距離以内ならワープを使う
Config.BotBananaDistance = 16     -- 相手がこの距離以内ならバナナを置く
Config.BotStuckSpeed = 0.75       -- これより遅い（スタッド/秒）状態が続くと行き詰まり
Config.BotStuckTime = 0.7         -- 行き詰まりとみなすまでの秒数（超えたらジャンプ）
Config.BotWaypointReach = 3.5     -- 経路の点にこの距離まで近づいたら次の点へ進む

-- 累計 RP から段位テーブルを返す。該当がなければ nil。
function Config.TierForRP(rp)
	rp = tonumber(rp) or 0
	local best = nil
	for _, tier in ipairs(Config.RankTiers) do
		if rp >= tier.MinRP and (best == nil or tier.MinRP >= best.MinRP) then
			best = tier
		end
	end
	return best
end

-- 次の段位。すでに最高段なら nil。
function Config.NextTierForRP(rp)
	rp = tonumber(rp) or 0
	local nextTier = nil
	for _, tier in ipairs(Config.RankTiers) do
		if tier.MinRP > rp and (nextTier == nil or tier.MinRP < nextTier.MinRP) then
			nextTier = tier
		end
	end
	return nextTier
end

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
		Tier = "B",
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
		Tier = "A",
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
		Tier = "A",
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
		Tier = "A",
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
		Tier = "S",
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
		Tier = "B",
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
		Tier = "B",
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
		Tier = "B",
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
		Tier = "B",
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
		Tier = "B",
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
		Tier = "A",
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
		Tier = "A",
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
		Tier = "A",
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
		Tier = "A",
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
		Tier = "S",
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
		Tier = "S",
		Price = 900,
		DisplayName = "セカンドチャンス",
		Description = "強制送還の回数を1回分なかったことにする",
		Color = Color3.fromRGB(255, 90, 90),
		SpawnWeight = 1,
		CanTaggerUse = true,
	},
	-----------------------------------------------------------------
	-- マップ専用アイテム（そのマップのボックスからだけ出る。ショップ・デッキには出ない）
	-----------------------------------------------------------------
	Phase = {
		Id = "Phase",
		DisplayName = "壁抜け",
		Description = "洞窟の内壁を2.5秒間すり抜ける",
		Color = Color3.fromRGB(180, 125, 255),
		SpawnWeight = 1,
		CanTaggerUse = true,
		ExclusiveMap = "Cave",
		Duration = 2.5,
	},
	SpikeBoots = {
		Id = "SpikeBoots",
		DisplayName = "スパイクブーツ",
		Description = "5秒間、氷の床で滑らなくなる",
		Color = Color3.fromRGB(120, 220, 255),
		SpawnWeight = 1,
		CanTaggerUse = true,
		ExclusiveMap = "Ice",
		Duration = 5,
	},
	Insulate = {
		Id = "Insulate",
		DisplayName = "絶縁",
		Description = "6秒間、帯電部品で痺れなくなる",
		Color = Color3.fromRGB(255, 240, 100),
		SpawnWeight = 1,
		CanTaggerUse = true,
		ExclusiveMap = "Volt",
		Duration = 6,
	},
	SafetyLine = {
		Id = "SafetyLine",
		DisplayName = "命綱",
		Description = "落下時に一度だけ、自動で最後の足場に戻る",
		Color = Color3.fromRGB(120, 230, 160),
		SpawnWeight = 1,
		CanTaggerUse = true,
		ExclusiveMap = "Sky",
		Passive = true,
	},
}


-- 氷上の水平速度を合成する。Y 方向の速度は呼び出し側で維持する。
function Config.IceVelocity(previous, direction, speed, dt)
	local input = Vector3.new(direction.X, 0, direction.Z)
	local moving = input.Magnitude > 0.01
	local rate = moving and Config.IceSlideSteering or Config.IceSlideDecay
	local blend = 1 - math.exp(-rate * dt)
	local target = input * speed
	local velocity = previous + (target - previous) * blend
	return velocity.Magnitude >= 0.1 and velocity or Vector3.new(0, 0, 0)
end

-- アイテムの並び順（ショップやデッキ画面の表示順）
Config.ItemOrder = {
	"Dash", "Banana", "HighJump", "Decoy", "Flash", "Sneak",
	"Warp", "Shield", "Smoke", "Glue", "AirBurst", "ZoneGuard", "Radar",
	"Star", "TimeStop", "SecondChance",
}

-- アイテムのレア度の表示（B = 150 / A = 400 / S = 900 コイン。以前の梅・竹・松）
Config.Tiers = {
	S = { Name = "S", Color = Color3.fromRGB(200, 40, 55) },
	A = { Name = "A", Color = Color3.fromRGB(230, 170, 30) },
	B = { Name = "B", Color = Color3.fromRGB(40, 165, 90) },
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
-- ひとりモード（ボットと遊ぶ）
---------------------------------------------------------------------
Config.SoloBotCount = 5            -- 一緒に走るボットの数
Config.SoloCoinRate = 0.5          -- ひとりモードでもらえるコインの割合
Config.StudioSoloAfter = 5         -- Studio で1人のまま何秒たったらボットで始めるか
Config.BotTaggerWalkSpeed = 17.5   -- 鬼になったボットの速さ（人の鬼 20 より遅め）
Config.BotRunnerWalkSpeed = 15     -- 逃げるボットの速さ（人 16 より少し遅め）

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

-- レア度の表示名を返す（"S" など）
function Config.GetTierName(tier)
	local info = Config.Tiers[tier]
	return info and info.Name or ""
end

return Config
