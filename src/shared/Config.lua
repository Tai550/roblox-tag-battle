-- Config: ゲームの数字（時間・速度・アイテム定義）をまとめた設定モジュール
-- ここだけを書き換えれば、ゲームバランスを調整できるようにしています。
-- 配置先: ReplicatedStorage.Shared.Config （サーバーとクライアントの両方から読む）

local Config = {}

---------------------------------------------------------------------
-- ラウンド進行
---------------------------------------------------------------------
Config.MinPlayers = 2            -- ラウンド開始に必要な最低人数（人間の数。ボットだけでは始まらない）
Config.BotFillTarget = 8         -- 人間がこれ未満なら、差分をボットで補う目標人数
Config.BotsEnabled = true        -- false にするとボット補充をしない
Config.IntermissionTime = 15     -- 待機（インターミッション）の秒数
Config.ResultsTime = 6           -- 結果表示の秒数

-- 試合時間はインターミッション中の投票で決める（同数・無投票なら DefaultDuration）
Config.MatchDurations = { 60, 180, 300 } -- 選べる試合時間（秒）: 1分・3分・5分
Config.DefaultDuration = 180     -- 投票が割れたとき・無投票のときの試合時間（秒）

---------------------------------------------------------------------
-- 移動速度
---------------------------------------------------------------------
Config.NormalWalkSpeed = 16      -- 逃げる人・観戦中の人の WalkSpeed
Config.IceSlideDecay = 1.7       -- 入力を離したときの減衰率（1/秒）
Config.IceSlideSteering = 3.5    -- 入力方向への追従率（1/秒）
Config.VoltStunTime = 1.2
Config.VoltRecoveryTime = 2
Config.FallEliminateY = 20      -- Sky の中央足場（Y=50）から30下

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
Config.ZoneWallHeight = 60         -- 壁（円柱）の高さ
Config.ZoneWallColor = Color3.fromRGB(255, 90, 200) -- 壁の色
Config.ZoneWallTransparency = 0.5  -- 壁の透明度

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
	Survived = "逃げ切り",        -- 鬼にならずにラウンドを終えた回数（累計。保存する）
	Tagged = "鬼タッチ",          -- 鬼にタッチされて鬼になった回数（累計。保存する）
	Rank = "ランク",              -- 段位名（例: ゴールド）
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

-- 通常アイテムの並び順（デッキ表示・購入抽選で使う）
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
