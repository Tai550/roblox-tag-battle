-- run_tests: v2 で追加した計算ロジックと、マップ生成（MapBuilder）のモックテスト
-- 実行前に `python3 tests/build_tests.py` で tests/.build/ を作っておくこと。
-- 実行: luau tests/run_tests.lua

local RT = require("./.build/mockenv")

-- 依存順に本物のモジュールを読み込み、モックの参照表へ登録する
RT.modules.Config = require("./.build/Config")
RT.modules.UILayout = require("./.build/UILayout")
RT.modules.BeastModels = require("./.build/BeastModels")
RT.modules.GameState = require("./.build/GameState")
RT.modules.Remotes = require("./.build/Remotes")
RT.modules.Leaderstats = require("./.build/Leaderstats")
RT.modules.PlayerDataStore = require("./.build/PlayerDataStore")
RT.modules.MatchSession = require("./.build/MatchSession")
RT.modules.RankManager = require("./.build/RankManager")
RT.modules.DeckManager = require("./.build/DeckManager")
RT.modules.ZoneManager = require("./.build/ZoneManager")
RT.modules.MapBuilder = require("./.build/MapBuilder")
RT.modules.ItemManager = require("./.build/ItemManager")
RT.modules.TaggerLook = require("./.build/TaggerLook")
RT.modules.BotManager = require("./.build/BotManager")
RT.modules.RoundManager = require("./.build/RoundManager")

local Config = RT.modules.Config
local RankManager = RT.modules.RankManager
local Remotes = RT.modules.Remotes
local ZoneManager = RT.modules.ZoneManager
local DeckManager = RT.modules.DeckManager
local ItemManager = RT.modules.ItemManager
local RoundManager = RT.modules.RoundManager
local PlayerDataStore = RT.modules.PlayerDataStore
local MapBuilder = RT.modules.MapBuilder
local TaggerLook = RT.modules.TaggerLook
local BotManager = RT.modules.BotManager
local Leaderstats = RT.modules.Leaderstats
local GameState = RT.modules.GameState
local Vector3 = RT.Vector3
local Color3 = RT.Color3

---------------------------------------------------------------------
-- 小さなテスト道具
---------------------------------------------------------------------

local passed, failed = 0, 0
local function check(name, condition)
	if condition then
		passed = passed + 1
		print("ok  -", name)
	else
		failed = failed + 1
		print("NG  -", name)
	end
end
local function near(a, b)
	return math.abs(a - b) < 0.001
end
local function point(x, y, z)
	return { Position = Vector3.new(x, y, z) }
end

---------------------------------------------------------------------
-- スマホ画面：本物のクライアントスクリプトをモック上で起動する
---------------------------------------------------------------------

do
	local layout = RT.modules.UILayout
	check("UI寸法表はスマホの最小寸法を満たす",
		layout.EdgeMargin >= 16 and layout.MinTouchSize >= 52 and layout.BottomClearance >= 100)

	-- 試合の画面は MatchHUD に一本化したため、古い画面スクリプトの起動テストは外した
end

math.randomseed(12345)

---------------------------------------------------------------------
-- 1. 縮小エリア：中心と開始半径
---------------------------------------------------------------------

do
	-- 2点 (0,0,0) と (30,0,40): 中心 (15,0,20)、最大距離 25 → 25+15=40 → 下限 50 に丸める
	local cx, cy, cz, radius = ZoneManager.ComputeGeometry({ point(0, 0, 0), point(30, 0, 40) }, false)
	check("中心は出現ポイントの平均", near(cx, 15) and near(cy, 0) and near(cz, 20))
	check("開始半径は最大距離+80（25+80）", near(radius, 105))

	-- 2点 (0,0,0) と (200,0,0): 中心 (100,0,0)、最大距離 100 → 115（上限内）
	local _, _, _, radius2 = ZoneManager.ComputeGeometry({ point(0, 0, 0), point(200, 0, 0) }, false)
	check("開始半径は設定した上限に丸める（200+80）", near(radius2, Config.ZoneStartRadiusMax))

	-- 離れた2点でも開始半径は設定値で頭打ちになる。
	local _, _, _, radius3 = ZoneManager.ComputeGeometry({ point(0, 0, 0), point(300, 0, 0) }, false)
	check("開始半径は設定した上限に丸める", near(radius3, Config.ZoneStartRadiusMax))

	-- 予備ポイントのみの場合は 60
	local _, _, _, radius4 = ZoneManager.ComputeGeometry({ point(0, 3, 0), point(10, 3, 0) }, true)
	check("予備ポイントのみなら開始半径60", near(radius4, 60))

	-- ポイントが空なら予備の中心と半径
	local fx, fy, fz, radius5 = ZoneManager.ComputeGeometry({}, false)
	check("ポイントなしは予備中心・半径60", near(fx, 0) and near(fy, 3) and near(fz, 0) and near(radius5, 60))
end

---------------------------------------------------------------------
-- 2. 縮小エリア：半径の時間変化（試合時間の80%で終了半径へ）
---------------------------------------------------------------------

do
	-- 180秒・開始半径175: 54秒(30%)までは縮まず、153秒(85%)で25まで縮む。中間103.5秒で100
	check("開始直後は開始半径", near(ZoneManager.RadiusAt(0, 180, 175), 175))
	check("30%までは縮まない", near(ZoneManager.RadiusAt(54, 180, 175), 175))
	check("縮小区間の中間で線形に縮む", near(ZoneManager.RadiusAt(103.5, 180, 175), 100))
	check("85%時点で終了半径25", near(ZoneManager.RadiusAt(153, 180, 175), 25))
	check("85%を過ぎたら終了半径で固定", near(ZoneManager.RadiusAt(180, 180, 175), 25))
	-- 60秒: 18秒まで縮まず、51秒で25
	check("60秒試合の途中経過", near(ZoneManager.RadiusAt(34.5, 60, 175), 100))
end

---------------------------------------------------------------------
-- 3. 縮小エリア：内外判定と、ボックス出現位置の絞り込み
---------------------------------------------------------------------

do
	check("中心は内側", ZoneManager.IsInsideXZ(0, 0, 50, Vector3.new(0, 0, 0)))
	check("境界上は内側", ZoneManager.IsInsideXZ(0, 0, 50, Vector3.new(50, 0, 0)))
	check("外は外", not ZoneManager.IsInsideXZ(0, 0, 50, Vector3.new(51, 0, 0)))
	check("高さは判定に入らない", ZoneManager.IsInsideXZ(0, 0, 50, Vector3.new(10, 999, 10)))

	local points = { point(10, 0, 10), point(100, 0, 0), point(50, 0, 0), point(0, 0, -60) }
	local inside = ItemManager.FilterPointsInZone(points, 0, 0, 50)
	check("ボックス出現位置はエリア内だけ（4点中2点）", #inside == 2)
end

---------------------------------------------------------------------
-- 4. デッキ：検証と、デッキ外のアイテムが出ないこと
---------------------------------------------------------------------

do
	local okValid = DeckManager.ValidateDeck({ "Dash", "Shield", "Warp", "Banana" })
	check("正しいデッキ（4個）は通る", okValid == true)
	local okDup = DeckManager.ValidateDeck({ "Dash", "Dash", "Warp", "Banana" })
	check("重複は通らない", okDup == false)
	local okCount = DeckManager.ValidateDeck({ "Dash", "Shield", "Warp" })
	check("数が違うと通らない", okCount == false)
	local okUnknown = DeckManager.ValidateDeck({ "Dash", "Shield", "Warp", "NoSuchItem" })
	check("存在しないアイテムは通らない", okUnknown == false)
	local okType = DeckManager.ValidateDeck("Dash")
	check("配列でないと通らない", okType == false)

	-- 保存データのデッキから300回引いて、デッキ外が出ないこと
	local fakePlayer = { Parent = {}, UserId = 1 }
	local deckSet = {}
	for _, itemId in ipairs(Config.DefaultDeck) do
		deckSet[itemId] = true
	end
	local seen = {}
	local allInside = true
	for _ = 1, 300 do
		local picked = DeckManager.PickFromDeck(fakePlayer)
		if not deckSet[picked] then
			allInside = false
		end
		seen[picked] = true
	end
	check("ボックス抽選はデッキの中からだけ出る", allInside)
	local seenCount = 0
	for _ in pairs(seen) do
		seenCount = seenCount + 1
	end
	check("300回引けばデッキの4種すべて出る", seenCount == 4)
end

---------------------------------------------------------------------
-- 4b. 保存データ：持っていないアイテムはデッキに入れられない・壊れたデータの修復
---------------------------------------------------------------------

do
	local fresh = PlayerDataStore.Normalize(nil)
	check("新しいデータはコイン0", fresh.Coins == 0)
	check("最初からスターターを持っている", fresh.Owned.Dash and fresh.Owned.Banana and fresh.Owned.Warp and fresh.Owned.Shield)
	check("最初のデッキは既定デッキ", #fresh.Deck == Config.DeckSize)
	local notOwned = PlayerDataStore.ValidateDeck({ "Dash", "Banana", "Warp", "TimeStop" }, fresh.Owned)
	check("持っていないアイテムはデッキに入らない", notOwned == false)
	local broken = PlayerDataStore.Normalize({ Coins = -50, Owned = { Fake = true, Star = true }, Deck = { "Star" } })
	check("マイナスのコインは0に直る", broken.Coins == 0)
	check("存在しないアイテムは持ち物から消える", broken.Owned.Fake == nil and broken.Owned.Star == true)
	check("壊れたデッキは既定デッキに戻る", #broken.Deck == Config.DeckSize)
	local bought = PlayerDataStore.Normalize({ Coins = 10, Owned = { TimeStop = true }, Deck = { "TimeStop", "Dash", "Banana", "Warp" } })
	check("買ったアイテム入りのデッキはそのまま", bought.Deck[1] == "TimeStop")
	local count = 0
	for _, itemId in ipairs(Config.ItemOrder) do
		if Config.Items[itemId] then
			count = count + 1
		end
	end
	check("アイテムは全部で16種（既存6＋追加10）", count == 16 and #Config.ItemOrder == 16)
	local tierOk = true
	for _, itemId in ipairs(Config.ItemOrder) do
		local def = Config.Items[itemId]
		if not Config.Tiers[def.Tier] then
			tierOk = false
		end
	end
	check("すべてのアイテムに松竹梅がある", tierOk)
end

---------------------------------------------------------------------
-- 4c. 順位とコイン
---------------------------------------------------------------------

do
	local results = RoundManager.ComputeResults({
		{ Key = "A", Tags = 2, FinalTagger = false },
		{ Key = "B", Tags = 0, FinalTagger = false, ChampionEligible = true },
		{ Key = "C", Tags = 1, FinalTagger = true },
		{ Key = "G", Tags = 0, FinalTagger = true },
		{ Key = "D", Tags = 0, FinalTagger = false, EliminatedOrder = 1 },
		{ Key = "E", Tags = 1, FinalTagger = false },
		{ Key = "F", Tags = 3, FinalTagger = false, EliminatedOrder = 2 },
	})
	local order = {}
	for _, entry in ipairs(results) do
		table.insert(order, entry.Key)
	end
	check("順位: 逃げ切り(少ない順)→最後の鬼→脱落(あとの人が上)", table.concat(order) == "BEACGFD")
	check("一度もタッチされずに逃げ切ったら優勝", results[1].Status == "優勝" and results[1].Champion == true)
	check("優勝がいちばんコインが多い", results[1].Coins > results[2].Coins and results[1].Coins == Config.CoinRewards.Champion)
	check("最後の鬼は負け", results[4].Status == "最後の鬼" and results[4].Coins == Config.CoinRewards.FinalTagger)
	check("最終時点の鬼は2人とも鬼として表示する", results[5].Status == "最後の鬼"
		and results[5].Coins == Config.CoinRewards.FinalTagger and not results[5].Champion)
	check("脱落は最下位グループ", results[7].Status == "脱落" and results[7].Key == "D")
	check("タッチされても脱落していないDは優勝にならない（脱落）", results[7].Champion == false)

	local formerTagger = RoundManager.ComputeResults({
		{ Key = "Former tagger", Tags = 0, FinalTagger = false, ChampionEligible = false },
	})[1]
	check("鬼から逃げ役に変わった人は被タッチ0回でも優勝しない",
		not formerTagger.Champion and formerTagger.Coins < Config.CoinRewards.Champion)

	local tie = RoundManager.ComputeResults({
		{ Key = "X", Tags = 0, FinalTagger = false, ChampionEligible = true },
		{ Key = "Y", Tags = 0, FinalTagger = false, ChampionEligible = true },
	})
	check("同じ回数なら同じ順位（同時優勝）", tie[1].Rank == 1 and tie[2].Rank == 1 and tie[2].Champion)
	local many = RoundManager.ComputeResults({ { Key = "Z", Tags = 9, FinalTagger = false } })
	check("タッチが多くても最低枚数はもらえる", many[1].Coins == Config.CoinRewards.SurvivorMin)

	check("送還0回では脱落しない", ZoneManager.ShouldEliminate(0) == false)
	check("送還2回のあとは脱落", ZoneManager.ShouldEliminate(Config.ZoneMaxReturns) == true)
end

---------------------------------------------------------------------
-- 5. 試合時間の投票：最多票・同数・無投票
---------------------------------------------------------------------

do
	local chosen0, counts0 = RoundManager.TallyVotes({})
	check("無投票なら既定の180秒", chosen0 == 180 and counts0[60] == 0 and counts0[180] == 0 and counts0[300] == 0)

	local chosen1 = RoundManager.TallyVotes({ a = 60, b = 60, c = 180 })
	check("最多票が採用される", chosen1 == 60)

	local chosen2 = RoundManager.TallyVotes({ a = 60, b = 300 })
	check("同数（既定が含まれない）でも既定の180秒", chosen2 == 180)

	local chosen3 = RoundManager.TallyVotes({ a = 300, b = 300, c = 60, d = 60 })
	check("2対2の同数でも既定の180秒", chosen3 == 180)

	local chosen4, counts4 = RoundManager.TallyVotes({ a = 999, b = 60 })
	check("候補にない票は数えない", chosen4 == 60 and counts4[60] == 1)

	local chosen5 = RoundManager.TallyVotes({ a = 300, b = 300, c = 300 })
	check("全員一致なら300秒", chosen5 == 300)
end

---------------------------------------------------------------------
-- 6. ゾーン開始の結合テスト（予備ポイントのマップを想定）
---------------------------------------------------------------------

do
	ZoneManager.Start(180)
	check("ゾーンが開始される", ZoneManager.IsActive() == true)
	check("予備マップでは開始半径60", near(ZoneManager.GetRadius(), 60))
	local centerPos = ZoneManager.GetCenter()
	check("中心は予備ポイントの平均（原点付近）", near(centerPos.X, 0) and near(centerPos.Z, 0))
	check("中心付近はエリア内", ZoneManager.IsInside(Vector3.new(0, 3, 0)))
	check("遠くはエリア外", not ZoneManager.IsInside(Vector3.new(500, 3, 0)))
	ZoneManager.Stop()
	check("終了するとゾーンは止まる", ZoneManager.IsActive() == false)
end

---------------------------------------------------------------------
-- 7. マップ生成（MapBuilder）：渋谷風の街と出現ポイント
---------------------------------------------------------------------

do
	local MapBuilder = RT.modules.MapBuilder
	local workspace = RT.workspace

	local function countChildrenNamed(parent, name)
		local n = 0
		for _, child in ipairs(parent:GetChildren()) do
			if child.Name == name then
				n = n + 1
			end
		end
		return n
	end
	local function baseParts(root)
		local list = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	local summary = MapBuilder.Build()
	local map = workspace:FindFirstChild("Map")
	local spawns = workspace:FindFirstChild(Config.ItemSpawnFolderName)
	check("Workspace.Map が作られる", map ~= nil)
	check("Workspace.ItemSpawns が作られる", spawns ~= nil)

	local spawnParts = spawns and baseParts(spawns) or {}
	check("出現ポイントは BasePart が12個", #spawnParts == 12)

	local allInside, allMarker = true, true
	for _, p in ipairs(spawnParts) do
		if math.abs(p.Position.X) > MapBuilder.Half or math.abs(p.Position.Z) > MapBuilder.Half then
			allInside = false
		end
		if not (p.Transparency == 1 and p.CanCollide == false and p.Anchored == true
			and p.Size.X <= 2 and p.Size.Y == 1 and p.Size.Z == p.Size.X) then
			allMarker = false
		end
	end
	check("出現ポイントはすべて舞台の範囲内（|x|,|z| <= 90）", allInside)
	check("出現ポイントは 高さ1・水平2以下・透明・当たり判定なし・固定", allMarker)

	local names = {}
	for _, p in ipairs(spawnParts) do
		names[p.Name] = true
	end
	local allNamed = true
	for i = 1, 12 do
		if not names["Spawn" .. i] then
			allNamed = false
		end
	end
	check("出現ポイントの名前は Spawn1〜Spawn12", allNamed)

	-- 横断歩道：白い Part（4方向 × 9本 = 36本を想定）
	local mapParts = map and baseParts(map) or {}
	local white = 0
	for _, p in ipairs(mapParts) do
		local c = p.Color
		if c and c.R == 255 and c.G == 255 and c.B == 255 then
			white = white + 1
		end
	end
	check("横断歩道の白い Part が4方向ぶん（36本以上）ある", white >= 36)

	local total = #mapParts + #spawnParts
	check("BasePart の総数は 700 以下", total <= 700)
	check("Build() の集計と実際の Part 数が一致", summary.PartCount == total)
	print(string.format("    （Map の BasePart %d ＋ 出現ポイント %d ＝ %d）", #mapParts, #spawnParts, total))

	-- 屋上に登れる建物（2〜3棟）と、屋上の出現ポイント（2点）
	check("屋上に登れる建物は2〜3棟", summary.ClimbableBuildings >= 2 and summary.ClimbableBuildings <= 3)
	print(string.format("    （屋上に登れる建物 %d 棟）", summary.ClimbableBuildings))
	local roofSpawns = 0
	for _, p in ipairs(MapBuilder.ItemSpawnPositions()) do
		if p.roof then
			roofSpawns = roofSpawns + 1
		end
	end
	check("屋上の出現ポイントは2点", roofSpawns == 2)

	-- 出現ポイントが建物の中に埋まっていない（屋上のものは屋上より上）
	local notBuried = true
	local scale = MapBuilder.RoadHalf / 18
	for _, p in ipairs(MapBuilder.ItemSpawnPositions()) do
		for _, b in ipairs(MapBuilder.Buildings) do
			local inX = math.abs(p.x - b.x * scale) < (b.w / 2 + 1) * scale
			local inZ = math.abs(p.z - b.z * scale) < (b.d / 2 + 1) * scale
			if inX and inZ and p.y < b.h then
				notBuried = false
			end
		end
	end
	check("出現ポイントは建物に埋まっていない", notBuried)

	-- スロープの高い端は屋上の高さ、側面はビルにぴったり接する
	local rampsOk = true
	for _, b in ipairs(MapBuilder.Buildings) do
		if b.ramp then
			local cx, _, width = MapBuilder.RampGeometry(b)
			if not near(math.abs(cx - b.x), b.w / 2 + width / 2) then
				rampsOk = false
			end
			-- スロープが他のビルにめり込んでいない
			for _, other in ipairs(MapBuilder.Buildings) do
				if other ~= b then
					local hitX = math.abs(cx - other.x) < (width + other.w) / 2
					local hitZ = math.abs(b.z - other.z) < (b.d + other.d) / 2
					if hitX and hitZ then
						rampsOk = false
					end
				end
			end
		end
	end
	check("スロープはビルの側面に接し、他のビルと重ならない", rampsOk)

	-- ビル20棟が舞台の中に収まり、道路（幅36）にはみ出さない
	local buildingsOk = #MapBuilder.Buildings == 20
	for _, b in ipairs(MapBuilder.Buildings) do
		local minX, maxX = b.x - b.w / 2, b.x + b.w / 2
		local minZ, maxZ = b.z - b.d / 2, b.z + b.d / 2
		if math.max(math.abs(minX), math.abs(maxX), math.abs(minZ), math.abs(maxZ)) > 110 then
			buildingsOk = false
		end
		if (minX < 18 and maxX > -18) or (minZ < 18 and maxZ > -18) then
			buildingsOk = false
		end
		if b.h < 20 or b.h > 70 then
			buildingsOk = false
		end
	end
	check("ビル20棟は道路にはみ出さず、高さ20〜70", buildingsOk)

	-- 冪等性：もう一度呼んでも Map / ItemSpawns は1つずつ、中身も同じ数
	local summary2 = MapBuilder.Build()
	check("2回目の Build() でも Map は1つだけ", countChildrenNamed(workspace, "Map") == 1)
	check("2回目の Build() でも ItemSpawns は1つだけ",
		countChildrenNamed(workspace, Config.ItemSpawnFolderName) == 1)
	check("2回目の Build() でも同じ Part 数", summary2.PartCount == summary.PartCount)

	-- 既存の出現ポイント読み込み（ItemManager）がそのまま連動する
	local points, isFallback = ItemManager.GetSpawnPoints()
	check("ItemManager が生成した12点を読む（予備ポイントではない）", #points == 12 and isFallback == false)
end

---------------------------------------------------------------------
-- 8. 段位：境界、加算と昇格、保存と復元、DataStore の失敗
---------------------------------------------------------------------

do
	local function tierName(rp)
		local tier = Config.TierForRP(rp)
		return tier and tier.Name or ""
	end

	check("RP 0 はブロンズ", tierName(0) == "ブロンズ")
	check("RP 99 はブロンズ", tierName(99) == "ブロンズ")
	check("RP 100 はシルバー", tierName(100) == "シルバー")
	check("RP 249 はシルバー", tierName(249) == "シルバー")
	check("RP 250 はゴールド", tierName(250) == "ゴールド")
	check("RP 499 はゴールド", tierName(499) == "ゴールド")
	check("RP 500 はプラチナ", tierName(500) == "プラチナ")
	check("RP 849 はプラチナ", tierName(849) == "プラチナ")
	check("RP 850 はダイヤ", tierName(850) == "ダイヤ")
	check("RP 1299 はダイヤ", tierName(1299) == "ダイヤ")
	check("RP 1300 はマスター", tierName(1300) == "マスター")
	check("RP 5000 もマスター", tierName(5000) == "マスター")

	local nextFrom99 = Config.NextTierForRP(99)
	check("99 の次の段はシルバー（100）", nextFrom99 ~= nil and nextFrom99.Name == "シルバー" and nextFrom99.MinRP == 100)
	local nextFrom250 = Config.NextTierForRP(250)
	check("250 の次の段はプラチナ", nextFrom250 ~= nil and nextFrom250.Name == "プラチナ")
	check("1300 に次の段はない", Config.NextTierForRP(1300) == nil)
	check("配点は仕様どおり", Config.RankPoints.Survived == 20 and Config.RankPoints.Tag == 6
		and Config.RankPoints.TaggedAll == 14 and Config.RankPoints.Caught == 4)
	check("DataStore 名は RankV1", Config.RankDataStoreName == "RankV1")

	-- モックの GetAsync / SetAsync / UpdateAsync
	local probe = RT.game:GetService("DataStoreService"):GetDataStore("RankV1Probe")
	probe:SetAsync("probe", { RP = 1, Survived = 0, Tagged = 0 })
	local gotProbe = probe:GetAsync("probe")
	local updated = probe:UpdateAsync("probe", function(old)
		return { RP = old.RP + 2, Survived = 1, Tagged = 0 }
	end)
	local cancelled = probe:UpdateAsync("probe", function()
		return nil
	end)
	check("SetAsync した値を GetAsync で読める", gotProbe ~= nil and gotProbe.RP == 1)
	check("UpdateAsync は加算して書き戻す", updated ~= nil and updated.RP == 3 and probe:GetAsync("probe").RP == 3)
	check("無いキーは nil、nil を返す UpdateAsync は更新しない", probe:GetAsync("missing") == nil and cancelled == nil
		and probe:GetAsync("probe").Survived == 1)

	local fired = { n = 0, last = nil }
	Remotes.RankUp.FireClient = function(_, _, rankName)
		fired.n = fired.n + 1
		fired.last = rankName
	end

	local function makePlayer(userId)
		local player = RT.Instance.new("Player")
		player.Name = "U" .. tostring(userId)
		player.UserId = userId
		player.Parent = RT.Instance.new("Folder")
		local folder = RT.Instance.new("Folder")
		folder.Name = "leaderstats"
		for _, key in ipairs({ "Survived", "Tagged", "RP" }) do
			local value = RT.Instance.new("IntValue")
			value.Name = Config.LeaderstatNames[key]
			value.Value = 0
			value.Parent = folder
		end
		local rank = RT.Instance.new("StringValue")
		rank.Name = Config.LeaderstatNames.Rank
		rank.Value = ""
		rank.Parent = folder
		folder.Parent = player
		return player
	end

	local function stat(player, key)
		local folder = player:FindFirstChild("leaderstats")
		local value = folder and folder:FindFirstChild(Config.LeaderstatNames[key])
		return value and value.Value
	end

	local initOk = pcall(function()
		RankManager.Init()
		RankManager.Init()
		if RT._bindToClose then
			RT._bindToClose()
		end
	end)
	check("Init と終了時保存はエラーで止まらない", initOk == true)

	local climber = makePlayer(42)
	RankManager.Load(climber)
	check("新規は RP 0 から", RankManager.Get(climber).RP == 0 and RankManager.Get(climber).LoadOk == true)
	RankManager.Award(climber, 99)
	check("99 では昇格しない", RankManager.Get(climber).RP == 99 and fired.n == 0 and stat(climber, "Rank") == "ブロンズ")
	RankManager.Award(climber, 1)
	check("100 でシルバーに上がり RankUp は1回", RankManager.Get(climber).RP == 100 and fired.n == 1 and fired.last == "シルバー")
	check("leaderstats の RP とランクが追従する", stat(climber, "RP") == 100 and stat(climber, "Rank") == "シルバー")
	RankManager.Award(climber, 50)
	RankManager.Award(climber, -10)
	RankManager.Award(climber, 0)
	check("段の途中の加算では RankUp は増えない", RankManager.Get(climber).RP == 150 and fired.n == 1)
	check("負の加算と 0 では RP は減らない", RankManager.Get(climber).RP == 150)

	fired.n = 0
	fired.last = nil
	local jumper = makePlayer(43)
	RankManager.Load(jumper)
	RankManager.Award(jumper, 1300)
	check("段をまとめて越えても RankUp は1回（マスター）", fired.n == 1 and fired.last == "マスター"
		and stat(jumper, "Rank") == "マスター")

	local saver = makePlayer(1001)
	RankManager.Load(saver)
	RankManager.Award(saver, 250)
	RankManager.AddCount(saver, "Survived")
	RankManager.AddCount(saver, "Survived")
	RankManager.AddCount(saver, "Tagged")
	RankManager.Save(saver)

	fired.n = 0
	fired.last = nil
	local loaded = makePlayer(1001)
	RankManager.Load(loaded)
	local restored = RankManager.Get(loaded)
	check("読み直すと RP が戻る", restored.RP == 250 and restored.LoadOk == true)
	check("読み直すと逃げ切りと鬼タッチが戻る", restored.Survived == 2 and restored.Tagged == 1)
	-- プレイヤーリストの「鬼回数」は試合ごとの回数なので、累計は書かない（RP とランクだけ）
	check("読み直した leaderstats も同じ", stat(loaded, "RP") == 250 and stat(loaded, "Survived") == 0
		and stat(loaded, "Tagged") == 0 and stat(loaded, "Rank") == "ゴールド")
	check("保存済みの段位を読み込んでも RankUp は飛ばない", fired.n == 0)
	RankManager.Load(loaded)
	check("同じ参加の再読み込みでは RP は増えない", RankManager.Get(loaded).RP == 250)
	local board = RT.game:GetService("DataStoreService"):GetOrderedDataStore(Config.RankLeaderboardStoreName)
	check("保存するとランキング（OrderedDataStore）にも累計 RP が載る", board:GetAsync("1001") == 250)

	-- 失敗しても止まらず 0 から。失敗中の保存で、すでに書いてある記録は消えない。
	RT.DataStoreShouldFail = true
	local failedLoadOk, failedSaveOk = true, true
	local failedPlayer = makePlayer(1001)
	local loadCallOk = pcall(function()
		RankManager.Load(failedPlayer)
	end)
	if not loadCallOk or RankManager.Get(failedPlayer).RP ~= 0 then
		failedLoadOk = false
	end
	local awardCallOk = pcall(function()
		RankManager.Award(failedPlayer, 50)
		RankManager.AddCount(failedPlayer, "Survived")
	end)
	if not awardCallOk then
		failedLoadOk = false
	end
	local saveCallOk = pcall(function()
		RankManager.Save(failedPlayer)
	end)
	if not saveCallOk then
		failedSaveOk = false
	end
	RT.DataStoreShouldFail = false
	local afterFail = makePlayer(1001)
	RankManager.Load(afterFail)
	local kept = RankManager.Get(afterFail)
	check("DataStore が失敗しても読み込みは止まらず 0 から", failedLoadOk and RankManager.Get(failedPlayer).RP == 50
		and RankManager.Get(failedPlayer).LoadOk == false)
	check("失敗中の保存でも止まらず、元の RP と回数は残る", failedSaveOk and kept.RP == 250 and kept.Survived == 2 and kept.Tagged == 1)
end

---------------------------------------------------------------------

---------------------------------------------------------------------
-- 9. 鬼の見た目：少し赤くして Highlight。交代とラウンド終了で元に戻る
---------------------------------------------------------------------

do
	local function sameColor(part, color)
		return part.Color ~= nil
			and near(part.Color.R, color.R)
			and near(part.Color.G, color.G)
			and near(part.Color.B, color.B)
	end

	local function makeCharacter(headColor, torsoColor, rootColor)
		local model = RT.Instance.new("Model")
		model.Name = "Character"
		local humanoid = RT.Instance.new("Humanoid")
		humanoid.Name = "Humanoid"
		humanoid.Health = 100
		humanoid.Parent = model
		local function addPart(name, color)
			local part = RT.Instance.new("Part")
			part.Name = name
			part.Color = color
			part.Parent = model
			return part
		end
		addPart("HumanoidRootPart", rootColor)
		local head = addPart("Head", headColor)
		local torso = addPart("Torso", torsoColor)
		return model, head, torso
	end

	local white = Color3.fromRGB(255, 255, 255)
	local blue = Color3.fromRGB(80, 120, 200)
	local skin = Color3.fromRGB(255, 204, 153)
	local mixedWhite = TaggerLook.MixColor(white)
	local mixedBlue = TaggerLook.MixColor(blue)

	check("赤を混ぜる割合は 0.45", TaggerLook.TintAlpha == 0.45)
	check("白に赤を 0.45 混ぜると少し赤い", near(mixedWhite.R, 255)
		and near(mixedWhite.G, 255 + (90 - 255) * 0.45)
		and near(mixedWhite.B, 255 + (90 - 255) * 0.45))
	check("真っ赤にはならない", mixedWhite.G > 140 and mixedWhite.B > 140)

	local playerA = RT.Instance.new("Player")
	playerA.Name = "TaggerA"
	local charA, headA, torsoA = makeCharacter(white, blue, skin)
	playerA.Character = charA

	local playerB = RT.Instance.new("Player")
	playerB.Name = "TaggerB"
	local charB, headB = makeCharacter(white, white, white)
	playerB.Character = charB

	GameState.Taggers = { [playerA] = { Since = 0 } }
	TaggerLook.Apply(playerA)
	local highlightA = charA:FindFirstChild(TaggerLook.HighlightName)
	check("鬼の各 Part が元の色と赤の中間になる", sameColor(headA, mixedWhite) and sameColor(torsoA, mixedBlue))
	check("鬼には Highlight が付き、塗りは薄め", highlightA ~= nil
		and highlightA.FillTransparency >= 0.6 and highlightA.FillTransparency < 1
		and highlightA.OutlineTransparency < 1)
	check("鬼でない人には色も Highlight も付かない", sameColor(headB, white)
		and charB:FindFirstChild(TaggerLook.HighlightName) == nil)

	TaggerLook.Apply(playerA)
	check("同じ鬼に二度付けても色は二重に混ざらない", sameColor(headA, mixedWhite)
		and not sameColor(headA, TaggerLook.MixColor(mixedWhite)))

	GameState.Taggers = { [playerB] = { Since = 0 } }
	TaggerLook.Clear(playerA)
	TaggerLook.Apply(playerB)
	local highlightB = charB:FindFirstChild(TaggerLook.HighlightName)
	check("交代すると前の鬼は元の色に戻り Highlight が消える", sameColor(headA, white)
		and sameColor(torsoA, blue) and charA:FindFirstChild(TaggerLook.HighlightName) == nil)
	check("次の鬼に色と Highlight が付く", sameColor(headB, mixedWhite) and highlightB ~= nil
		and highlightB.FillTransparency >= 0.6)

	local fresh = Color3.fromRGB(10, 20, 30)
	local charB2, headB2 = makeCharacter(fresh, fresh, fresh)
	playerB.Character = charB2
	TaggerLook.OnCharacterAdded(playerB)
	check("鬼のままリスポーンすると新しい体に付け直す", charB:FindFirstChild(TaggerLook.HighlightName) == nil
		and sameColor(headB2, TaggerLook.MixColor(fresh))
		and charB2:FindFirstChild(TaggerLook.HighlightName) ~= nil)

	GameState.Taggers = {}
	TaggerLook.ClearAll()
	check("ラウンド終了で全員の色と Highlight が外れる", sameColor(headA, white)
		and sameColor(headB2, fresh) and sameColor(torsoA, blue)
		and charA:FindFirstChild(TaggerLook.HighlightName) == nil
		and charB2:FindFirstChild(TaggerLook.HighlightName) == nil)
	TaggerLook.OnCharacterAdded(playerA)
	check("鬼でないときのリスポーンでは色を付けない", sameColor(headA, white)
		and charA:FindFirstChild(TaggerLook.HighlightName) == nil)
end

---------------------------------------------------------------------
-- 10. マップの入れ替え：渋谷 → パーク → 渋谷。点数と範囲、ゾーン半径
---------------------------------------------------------------------

do
	local workspace = RT.workspace

	local function baseParts(root)
		local list = {}
		if not root then
			return list
		end
		for _, desc in ipairs(root:GetDescendants()) do
			if desc:IsA("BasePart") then
				table.insert(list, desc)
			end
		end
		return list
	end

	local function spawnFolder()
		return workspace:FindFirstChild(Config.ItemSpawnFolderName)
	end

	local baseline = MapBuilder.Build()
	check("Build() は渋谷のまま（ローテーションの回数は進めない）", baseline.MapId == "Shibuya"
		and MapBuilder.CurrentMap == "Shibuya" and baseline.ItemSpawns == 12)

	-- アリーナ（Rojo のマップ）はテストに無いので、渋谷とパークの2つで入れ替えを確かめる
	MapBuilder.ResetRotation({ "Shibuya", "Park", "Cave", "Ice", "Volt", "Sky" }, 1)
	local first = MapBuilder.BuildNextRound()
	local firstSpawns = baseParts(spawnFolder())
	local firstInside = true
	for _, part in ipairs(firstSpawns) do
		if math.abs(part.Position.X) > MapBuilder.Half or math.abs(part.Position.Z) > MapBuilder.Half then
			firstInside = false
		end
	end
	check("入れ替え1回目は渋谷（12点・同じ Part 数）", first.MapId == "Shibuya"
		and MapBuilder.CurrentMap == "Shibuya" and #firstSpawns == 12
		and first.PartCount == baseline.PartCount and first.ClimbableBuildings >= 2)
	check("渋谷の Workspace 属性が一致する", workspace:GetAttribute("CurrentMap") == "Shibuya"
		and workspace:GetAttribute("CurrentGimmick") == "None")
	check("渋谷の出現ポイントは従来の範囲内", firstInside)
	local shibuyaPoints, shibuyaFallback = ItemManager.GetSpawnPoints()
	check("渋谷の出現ポイントを ItemManager がそのまま読む", #shibuyaPoints == 12 and shibuyaFallback == false)

	local second = MapBuilder.BuildNextRound()
	check("パークの Workspace 属性が一致する", workspace:GetAttribute("CurrentMap") == "Park"
		and workspace:GetAttribute("CurrentGimmick") == "None")
	local parkMap = workspace:FindFirstChild("Map")
	local parkSpawns = baseParts(spawnFolder())
	local parkParts = baseParts(parkMap)
	local inPark, spreadsBeyond, hasPos, hasNeg = true, false, false, false
	for _, part in ipairs(parkSpawns) do
		if math.abs(part.Position.X) > MapBuilder.ParkHalf or math.abs(part.Position.Z) > MapBuilder.ParkHalf then
			inPark = false
		end
		if math.abs(part.Position.X) > MapBuilder.Half or math.abs(part.Position.Z) > MapBuilder.Half then
			spreadsBeyond = true
		end
		if part.Position.X > 0 or part.Position.Z > 0 then
			hasPos = true
		end
		if part.Position.X < 0 or part.Position.Z < 0 then
			hasNeg = true
		end
	end
	local spawnLocations = 0
	local spawnAtCenter = false
	local wallCount = 0
	local grassOk = false
	local white = 0
	for _, part in ipairs(parkParts) do
		if part.ClassName == "SpawnLocation" then
			spawnLocations = spawnLocations + 1
			if math.abs(part.Position.X) < 1 and math.abs(part.Position.Z) < 1 then
				spawnAtCenter = true
			end
		end
		if part.Name == "InvisibleWall" and part.Transparency == 1 then
			wallCount = wallCount + 1
		end
		if part.Name == "Grass" and near(part.Size.X, 180) and near(part.Size.Z, 180) then
			grassOk = true
		end
		local color = part.Color
		if color and color.R == 255 and color.G == 255 and color.B == 255 then
			white = white + 1
		end
	end
	check("入れ替え2回目はパーク（14点）", second.MapId == "Park" and MapBuilder.CurrentMap == "Park"
		and second.ItemSpawns == 14 and #parkSpawns == 14 and #MapBuilder.ParkSpawnPositions() == 14)
	-- 出現ポイントは外周の内側で、四方に散らばる。
	check("パークの出現ポイントは縮小後の範囲内で、四方に散らばる", not spreadsBeyond and hasPos and hasNeg)
	check("パークの Part 数は 500 以下", second.PartCount <= 500 and second.PartCount == #parkParts + #parkSpawns)
	print(string.format("    （パークの BasePart %d ＋ 出現ポイント %d ＝ %d）", #parkParts, #parkSpawns, second.PartCount))
	check("パークは中央広場にスポーンが1つ、外周の透明な壁が4枚、芝生の地面", spawnLocations == 1
		and spawnAtCenter and wallCount == 4 and grassOk)
	check("パークは渋谷の横断歩道（白い帯）を持たない", white < 36 and second.ClimbableBuildings == 0)

	local parkPoints, parkFallback = ItemManager.GetSpawnPoints()
	local _, _, _, parkRadius = ZoneManager.ComputeGeometry(parkPoints, false)
	check("パークの出現ポイントでもゾーンの開始半径が計算できる", #parkPoints == 14 and parkFallback == false
		and parkRadius >= Config.ZoneStartRadiusMin and parkRadius <= Config.ZoneStartRadiusMax)
	check("広いパークの開始半径は設定した上限に丸まる", near(parkRadius, Config.ZoneStartRadiusMax))

	-- 明示的な Build() は表示中のマップだけを作り直す。
	local rebuilt = MapBuilder.Build()
	check("途中の Build() は渋谷を作り直すだけ", rebuilt.MapId == "Shibuya" and MapBuilder.CurrentMap == "Shibuya")
	local lighting = RT.game:GetService("Lighting")
	local originalBrightness = lighting.Brightness
	local dungeonLimits = { Cave = 400, Ice = 300, Volt = 350, Sky = 300 }
	for _, expected in ipairs({
		{ "Cave", "Cave", "Phase" },
		{ "Ice", "Ice", "SpikeBoots" },
		{ "Volt", "Volt", "Insulate" },
		{ "Sky", "None", "SafetyLine" },
		{ "Shibuya", "None" },
	}) do
		local id, gimmick, item = table.unpack(expected)
		local summary = MapBuilder.BuildNextRound()
		local info = MapBuilder.GetCurrentMapInfo()
		check(id .. " に進み、属性とマップ情報が一致する", summary.MapId == id and MapBuilder.CurrentMap == id
			and info.Id == id and info.Gimmick == gimmick and info.ExclusiveItemId == item
			and RT.workspace:GetAttribute("CurrentMap") == id and RT.workspace:GetAttribute("CurrentGimmick") == gimmick)
		check(id .. " の出現ポイントは12点", #baseParts(spawnFolder()) == 12 and summary.ItemSpawns == 12)
		if dungeonLimits[id] then
			local count = #baseParts(RT.workspace:FindFirstChild(MapBuilder.MapFolderName)) + #baseParts(spawnFolder())
			check(id .. " の Part 数は集計と上限に合う（実測 " .. count .. "）",
				count == summary.PartCount and count <= dungeonLimits[id])
		end
		local map = RT.workspace:FindFirstChild(MapBuilder.MapFolderName)
		local half = MapBuilder.Half
		local inside = true
		for _, part in ipairs(baseParts(spawnFolder())) do
			inside = inside and math.abs(part.Position.X) + part.Size.X / 2 <= half
				and math.abs(part.Position.Z) + part.Size.Z / 2 <= half
		end
		local surfaceNames = { Shibuya = "Base", Cave = "StoneFloor", Ice = "IceFloor", Volt = "MetalFloor" }
		local surfaceFolder = id == "Shibuya" and map:FindFirstChild("Ground") or map
		local surface = surfaceFolder:FindFirstChild(surfaceNames[id] or "")
		local playerSpawn = map:FindFirstChild("PlayerSpawn", true)
		check(id .. " の出現ポイントとゾーン上限は縮小後の範囲内",
			inside and playerSpawn ~= nil
			and math.abs(playerSpawn.Position.X) + playerSpawn.Size.X / 2 <= half
			and math.abs(playerSpawn.Position.Z) + playerSpawn.Size.Z / 2 <= half
			and map:GetAttribute("WalkableHalfExtent") == half)
		if surfaceNames[id] then
			check(id .. " の地面は180×180", surface and near(surface.Size.X, 180) and near(surface.Size.Z, 180))
		end
		if id == "Sky" then
			local platforms = baseParts(map:FindFirstChild("SkyPlatforms"))
			local bridges = baseParts(map:FindFirstChild("SkyBridges"))
			local extent = 0
			for _, part in ipairs(platforms) do
				extent = math.max(extent, math.abs(part.Position.X) + part.Size.X / 2,
					math.abs(part.Position.Z) + part.Size.Z / 2)
			end
			local connected = #platforms == 9 and #bridges == 12
			for _, bridge in ipairs(bridges) do
				local horizontal = bridge.Size.X > bridge.Size.Z
				local ends = { false, false }
				for _, platform in ipairs(platforms) do
					local dx = platform.Position.X - bridge.Position.X
					local dz = platform.Position.Z - bridge.Position.Z
					if math.abs(dx) < (platform.Size.X + bridge.Size.X) / 2
						and math.abs(dz) < (platform.Size.Z + bridge.Size.Z) / 2 then
						ends[(horizontal and dx or dz) < 0 and 1 or 2] = true
					end
				end
				connected = connected and ends[1] and ends[2]
			end
			check("落下マップは180×180で、12本の橋の両端が足場に重なる", near(extent, 90) and connected)
		end
		if id == "Cave" then
			check("洞窟では暗くなる", lighting.Brightness < originalBrightness)
			-- 2スタッド格子に、R15が通れるだけの余白を取って実際の回転した壁を投影する。
			local walls = baseParts(map:FindFirstChild("CaveInnerWalls"))
			local step, limit, clearance = 2, 86, 2
			local function key(x, z)
				return (x + limit) * (2 * limit + 1) + z + limit
			end
			local function isOpen(x, z)
				for _, wall in ipairs(walls) do
					local point = wall.CFrame:PointToObjectSpace(Vector3.new(x, 4, z))
					if math.abs(point.X) < wall.Size.X / 2 + clearance
						and math.abs(point.Z) < wall.Size.Z / 2 + clearance then
						return false
					end
				end
				return true
			end
			local walkable = {}
			for x = -limit, limit, step do
				for z = -limit, limit, step do
					walkable[key(x, z)] = isOpen(x, z)
				end
			end
			local offsets = { { -step, 0 }, { step, 0 }, { 0, -step }, { 0, step } }
			local function flood(x, z, visited)
				local queue = { { x, z } }
				visited[key(x, z)] = true
				local index = 1
				while index <= #queue do
					local point = queue[index]
					index += 1
					local px, pz = table.unpack(point)
					for _, offset in ipairs(offsets) do
						local nx, nz = px + offset[1], pz + offset[2]
						local cell = key(nx, nz)
						if math.abs(nx) <= limit and math.abs(nz) <= limit
							and walkable[cell] and not visited[cell] then
							visited[cell] = true
							table.insert(queue, { nx, nz })
						end
					end
				end
			end

			local reached = {}
			flood(0, 0, reached)
			local connected = walkable[key(0, 0)]
			local vertices, edges, squares = 0, 0, 0
			local deadEnds = {}
			for x = -limit, limit, step do
				for z = -limit, limit, step do
					local cell = key(x, z)
					if walkable[cell] then
						connected = connected and reached[cell] == true
						vertices += 1
						local degree = 0
						for _, offset in ipairs(offsets) do
							if walkable[key(x + offset[1], z + offset[2])] then
								degree += 1
							end
						end
						edges += degree
						if degree == 1 then
							table.insert(deadEnds, Vector3.new(x, 0, z))
						end
						if walkable[key(x + step, z)] and walkable[key(x, z + step)]
							and walkable[key(x + step, z + step)] then
							squares += 1
						end
					end
				end
			end
			local itemsNearDeadEnds = 0
			for _, part in ipairs(baseParts(spawnFolder())) do
				local x = step * math.round(part.Position.X / step)
				local z = step * math.round(part.Position.Z / step)
				connected = connected and reached[key(x, z)] == true
				for _, deadEnd in ipairs(deadEnds) do
					if (deadEnd - Vector3.new(part.Position.X, 0, part.Position.Z)).Magnitude <= 12 then
						itemsNearDeadEnds += 1
						break
					end
				end
			end
			check("洞窟の全通路とアイテム出現点は中央から到達できる", connected)
			-- 連結グラフの独立な輪 E - V + 1 から、単位正方形の輪を除く。
			check("洞窟には格子の小さな正方形を除いて独立な輪が2つ以上ある",
				connected and edges / 2 - vertices + 1 - squares >= 2)
			check("洞窟の次数1の歩行マスの近くにアイテム出現点がある", itemsNearDeadEnds >= 1)
		elseif id == "Ice" then
			check("氷床では照明が元に戻る", lighting.Brightness == originalBrightness)
		end
	end
	check("渋谷とパークの属性はギミックなし", RT.workspace:GetAttribute("CurrentGimmick") == "None"
		and first.MapId == "Shibuya" and second.MapId == "Park")
end

---------------------------------------------------------------------
-- 11. フィールドの宝箱：複数 Part、触れると従来どおりアイテムが手に入る
---------------------------------------------------------------------

do
	local players = RT.game:GetService("Players")
	local savedLookup = players.GetPlayerFromCharacter
	local savedMotionNow = ItemManager.MotionNow
	local ok, err = pcall(function()
		MapBuilder.Build()
		ZoneManager.Stop()
		GameState.Phase = "Round"
		GameState.Taggers = {}

		local player = RT.Instance.new("Player")
		player.Name = "Picker"
		player.Parent = RT.Instance.new("Folder")
		local character = RT.Instance.new("Model")
		character.Name = "PickerCharacter"
		local humanoid = RT.Instance.new("Humanoid")
		humanoid.Name = "Humanoid"
		humanoid.Health = 100
		humanoid.Parent = character
		local hand = RT.Instance.new("Part")
		hand.Name = "RightHand"
		hand.Parent = character
		player.Character = character
		GameState.Participants[player] = true
		players.GetPlayerFromCharacter = function(_, model)
			if model == character then
				return player
			end
			return nil
		end

		local now = 10000
		ItemManager.MotionNow = function()
			return now
		end
		ItemManager.Start()
		ItemManager.SpawnOne()

		local container = RT.workspace:FindFirstChild("SpawnedItems")
		local box = nil
		for _, child in ipairs(container and container:GetChildren() or {}) do
			if child.Name == "ItemBox" then
				box = child
			end
		end
		check("フィールドに ItemBox が出る", box ~= nil)
		check("浮遊の接続が1つ付く", ItemManager.ActiveBoxMotions() == 1)

		local partCount = 0
		if box and box:IsA("BasePart") then
			partCount = 1
		end
		for _, desc in ipairs(box and box:GetDescendants() or {}) do
			if desc:IsA("BasePart") then
				partCount = partCount + 1
			end
		end
		check("宝箱は複数の Part からなる", partCount >= 8)
		local piecesOk = box ~= nil
		for _, name in ipairs({
			"Lid", "LidTrimFront", "LidTrimBack", "BandFront", "BandBack", "BandTop", "Keyhole", "SeamGlow",
		}) do
			if not box or not box:FindFirstChild(name) then
				piecesOk = false
			end
		end
		check("蓋・金色の縁と帯・鍵穴・光の線がある", piecesOk)
		local seam = box and box:FindFirstChild("SeamGlow")
		check("本体は木、境目は Neon、PointLight が付く", box ~= nil
			and box.Material == RT.Enum.Material.Wood
			and seam ~= nil and seam.Material == RT.Enum.Material.Neon
			and seam:FindFirstChild("ChestGlow") ~= nil)
		local gui = box and box:FindFirstChildOfClass("BillboardGui")
		local label = gui and gui:FindFirstChild("Label")
		local textColor = label and label.TextColor3
		check("ラベルは宝箱の文言と色", label ~= nil and label.Text == "宝箱"
			and textColor ~= nil and not (textColor.R == textColor.G and textColor.G == textColor.B))

		local originX = box.Position.X
		local originY = box.Position.Y
		now = 10000.5
		RT.game:GetService("RunService").Heartbeat:_Fire()
		check("0.5秒で 0.4 スタッド上がる", near(box.CFrame.Y, originY + 0.4) and near(box.CFrame.X, originX))
		now = 10001
		RT.game:GetService("RunService").Heartbeat:_Fire()
		check("1秒で元の高さに戻り、30度回る", near(box.CFrame.Y, originY) and near(box.CFrame.RotY, math.rad(30)))
		local bob, yaw = ItemManager.BoxMotionAt(1.5)
		check("1.5秒の計算は下へ 0.4、45度", near(bob, -0.4) and near(yaw, math.rad(45)))

		local lid = box:FindFirstChild("Lid")
		lid.Touched:_Fire(hand)
		local data = GameState.GetData(player)
		local fromDeck = table.find(DeckManager.GetDeck(player), data.HeldItems[1]) ~= nil
		-- 使用期限なし（BoxExpireTime = 0）なので、期限は 0 のまま
		check("蓋に触れてもデッキのアイテムが1つ手に入る", #data.HeldItems == 1 and fromDeck
			and data.HeldExpireAt[1] == 0)
		check("拾うと箱は消え、浮遊の接続も残らない", box.Parent == nil and ItemManager.ActiveBoxMotions() == 0)

		box.CFrame = RT.CFrame.new(1, 2, 3)
		now = 10004
		RT.game:GetService("RunService").Heartbeat:_Fire()
		check("消したあとの Heartbeat ではもう動かない", near(box.CFrame.X, 1) and near(box.CFrame.Y, 2) and near(box.CFrame.Z, 3))

		ItemManager.Stop()
		GameState.Participants[player] = nil
		GameState.ClearData(player)
		GameState.Phase = "Waiting"
	end)
	ItemManager.MotionNow = savedMotionNow
	players.GetPlayerFromCharacter = savedLookup
	if not ok then
		error(err)
	end
end

---------------------------------------------------------------------

---------------------------------------------------------------------
-- 12. ボット：補充人数、強さの上限、Remote と保存のガード
---------------------------------------------------------------------

do
	check("人間3人・目標8ならボット5体", BotManager.CountToSpawn(3) == 5)
	check("人間2人なら目標まで6体", BotManager.CountToSpawn(2) == 6)
	check("人間7人なら1体", BotManager.CountToSpawn(7) == 1)
	check("人間8人ならボット0", BotManager.CountToSpawn(8) == 0)
	check("人間9人以上ならボット0", BotManager.CountToSpawn(9) == 0)
	check("人間が最低人数未満なら補充しない", BotManager.CountToSpawn(1) == 0 and BotManager.CountToSpawn(0) == 0)

	local savedEnabled = Config.BotsEnabled
	Config.BotsEnabled = false
	check("ボット無効なら人数が足りなくても補充しない", BotManager.CountToSpawn(3) == 0)
	Config.BotsEnabled = savedEnabled

	check("RP 0 は段位表の1（ブロンズ）", BotManager.TierIndexForRP(0) == 1)
	check("RP 250 は段位表の3（ゴールド）", BotManager.TierIndexForRP(250) == 3)
	check("RP 1300 は段位表の6（マスター）", BotManager.TierIndexForRP(1300) == 6)
	check("平均は四捨五入（1と2なら2）", BotManager.AverageTierIndex({ 1, 2 }) == 2)
	check("平均が空ならブロンズ", BotManager.AverageTierIndex({}) == 1)

	local previousSpeed = 0
	local previousInterval = math.huge
	local speedsRise = true
	local intervalsFall = true
	for index = 1, #Config.RankTiers do
		local speed, interval = BotManager.StrengthForTierIndex(index)
		if speed <= previousSpeed or speed > Config.BotSpeedMultiplierCap then
			speedsRise = false
		end
		if interval >= previousInterval then
			intervalsFall = false
		end
		previousSpeed = speed
		previousInterval = interval
	end
	check("段位が上がるほど速さ倍率は上がり、上限以下", speedsRise)
	check("段位が上がるほど経路の引き直しは短くなる", intervalsFall)

	local lowSpeed = BotManager.StrengthForTierIndex(BotManager.AverageTierIndex({ 1, 1, 2 }))
	local highSpeed = BotManager.StrengthForTierIndex(BotManager.AverageTierIndex({ 5, 6, 6 }))
	check("平均段位が高いほど倍率が大きい", highSpeed > lowSpeed and highSpeed <= Config.BotSpeedMultiplierCap)

	local savedCapRow = Config.BotStrengthByTier[6].SpeedMultiplier
	Config.BotStrengthByTier[6].SpeedMultiplier = 3
	local capped = BotManager.StrengthForTierIndex(6)
	local cappedOver = BotManager.StrengthForTierIndex(99)
	Config.BotStrengthByTier[6].SpeedMultiplier = savedCapRow
	check("表の値が大きくても速さ倍率は上限で止まる", capped == Config.BotSpeedMultiplierCap
		and cappedOver == Config.BotSpeedMultiplierCap)
	check("上限テストのあと表の値は戻る", Config.BotStrengthByTier[6].SpeedMultiplier == savedCapRow)

	local fleeX, _, fleeReason = BotManager.ChooseGoal({
		Role = "Runner",
		X = 0,
		Z = 0,
		TaggerX = 5,
		TaggerZ = 0,
		Boxes = { { X = 10, Z = 0 } },
	})
	check("鬼が近いときは宝箱を諦めて離れる", fleeReason == "flee" and fleeX < 0)

	local itemX, itemZ, itemReason = BotManager.ChooseGoal({
		Role = "Runner",
		X = 0,
		Z = 0,
		Boxes = { { X = 10, Z = 0 } },
	})
	check("鬼が遠い（いない）ときは近くの宝箱へ向かう", itemReason == "item" and itemX == 10 and itemZ == 0)

	local zoneX, _, zoneReason = BotManager.ChooseGoal({
		Role = "Runner",
		X = 48,
		Z = 0,
		ZoneActive = true,
		ZoneX = 0,
		ZoneZ = 0,
		ZoneRadius = 50,
		TaggerX = 40,
		TaggerZ = 0,
	})
	check("エリアの外に出そうなら内側へ戻る", zoneReason == "zone" and math.abs(zoneX) < 48)

	local chaseX, _, chaseReason = BotManager.ChooseGoal({
		Role = "Tagger",
		X = 0,
		Z = 0,
		Runners = { { X = 100, Z = 0 }, { X = 12, Z = 0 } },
	})
	check("鬼はいちばん近い逃げる人を追う", chaseReason == "chase" and chaseX == 12)

	local blindX, _, blindReason = BotManager.ChooseGoal({
		Role = "Tagger",
		X = 0,
		Z = 0,
		Blind = true,
		BlindAngle = 0,
		Runners = { { X = 5, Z = 0 } },
	})
	check("スモーク中のボット鬼は追わずに歩く", blindReason == "blind" and near(blindX, Config.BotFleeDistance))

	check("ボットはスモークを使わない", BotManager.ShouldUseItem("Smoke", false, 5) == false)
	check("逃げ中、鬼が近ければダッシュする", BotManager.ShouldUseItem("Dash", false, 20) == true)
	check("鬼のボットはダッシュ条件では使わない", BotManager.ShouldUseItem("Dash", true, 10) == false)
	check("鬼が近いときシールドを使う", BotManager.ShouldUseItem("Shield", false, 10) == true)
	check("鬼が遠いときシールドは使わない", BotManager.ShouldUseItem("Shield", false, 100) == false)

	local stuckTime, shouldJump = BotManager.UpdateStuck(0, 0, 0.4, 0.75, 0.7)
	check("ほぼ止まっていると行き詰まりが溜まる", near(stuckTime, 0.4) and shouldJump == false)
	stuckTime, shouldJump = BotManager.UpdateStuck(stuckTime, 0, 0.4, 0.75, 0.7)
	check("行き詰まりが続くとジャンプする", shouldJump == true)
	stuckTime, shouldJump = BotManager.UpdateStuck(0.5, 10, 0.4, 0.75, 0.7)
	check("動いていれば行き詰まりはリセット", stuckTime == 0 and shouldJump == false)

	local calls = {}
	local function spy(eventName)
		return function(_, target)
			table.insert(calls, { eventName, target })
		end
	end
	Remotes.Notify.FireClient = spy("Notify")
	Remotes.ItemUpdate.FireClient = spy("ItemUpdate")
	Remotes.RankUp.FireClient = spy("RankUp")
	Remotes.ZoneUpdate.FireClient = spy("ZoneUpdate")
	Remotes.SmokeEffect.FireClient = spy("Smoke")
	Remotes.PassUpdate.FireClient = spy("Pass")

	local bot = {
		IsBot = true,
		Name = "ボット9",
		DisplayName = "ボット9",
		UserId = -9,
		Parent = RT.Instance.new("Folder"),
	}
	local guardOk = pcall(function()
		RankManager.Award(bot, 500)
		RankManager.AddCount(bot, "Tagged")
		RankManager.AddCount(bot, "Survived")
		RankManager.Save(bot)
		RankManager.Load(bot)
		Leaderstats.Set(bot, "RP", 5)
		Leaderstats.Increment(bot, "Survived")
		Remotes.NotifyPlayer(bot, "ボットには届かない")
		ItemManager.SendItemUpdate(bot)
		DeckManager.GetDeck(bot)
		DeckManager.Release(bot)
	end)
	local store = RT.game:GetService("DataStoreService"):GetDataStore(Config.RankDataStoreName)
	local record = RankManager.Get(bot)
	check("ボットへの保存・加算はエラーにならない", guardOk == true)
	check("ボットは RankManager の保存対象にならない", store:GetAsync("-9") == nil)
	check("ボットの RP と回数は増えない", record.RP == 0 and record.Tagged == 0 and record.Survived == 0)

	local human = RT.Instance.new("Player")
	human.Name = "HumanNotify"
	human.Parent = RT.Instance.new("Folder")
	Remotes.NotifyPlayer(human, "人間には届く")

	local model = RT.Instance.new("Model")
	local humanoid = RT.Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.Health = 100
	humanoid.Parent = model
	local root = RT.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = RT.Vector3.new(0, 5, 0)
	root.Parent = model
	bot.Character = model
	GameState.Participants[bot] = true
	ZoneManager.Start(180)
	ZoneManager.Stop()
	GameState.Participants[bot] = nil
	GameState.ClearData(bot)

	local botHits = 0
	local humanHits = 0
	for _, call in ipairs(calls) do
		if call[2] == bot or (type(call[2]) == "table" and call[2].IsBot == true) then
			botHits = botHits + 1
		end
		if call[2] == human then
			humanHits = humanHits + 1
		end
	end
	check("Remotes の FireClient はボットに飛ばない", botHits == 0)
	check("人間への Notify は飛ぶ", humanHits == 1)

	GameState.Phase = "Round"
	GameState.Taggers = {}
	local humans = { {}, {}, {} }
	local players = RT.game:GetService("Players")
	local createRig = players.CreateHumanoidModelFromDescription
	local descriptions = {}
	players.CreateHumanoidModelFromDescription = function(_, description, rigType)
		table.insert(descriptions, { Description = description, RigType = rigType })
		return nil
	end
	BotManager.Fill(humans)
	players.CreateHumanoidModelFromDescription = createRig
	local muscular = Config.BotMuscular and #descriptions == 5
	for _, call in ipairs(descriptions) do
		local desc = call.Description
		muscular = muscular and call.RigType == RT.Enum.HumanoidRigType.R15
			and desc.WidthScale == 1.3 and desc.DepthScale == 1.25 and desc.BodyTypeScale == 0
			and desc.ProportionScale == 0 and desc.TorsoColor ~= nil
	end
	check("全ボットの標準R15生成で幅広い体型と体の色を渡す", muscular)
	local spawned = BotManager.GetActive()
	check("Fill は5体を参加者にする", BotManager.ActiveCount() == 5 and #spawned == 5)
	local namesOk = spawned[1] ~= nil and spawned[1].Name == "ボット1" and spawned[1].UserId == -1
		and spawned[2] ~= nil and spawned[2].UserId == -2 and spawned[5].Name == "ボット5"
	check("名前はボット1から、UserId は -1 からの連番", namesOk)
	local allJoined = true
	for _, spawnedBot in ipairs(spawned) do
		if not GameState.IsParticipant(spawnedBot) or spawnedBot.IsBot ~= true then
			allJoined = false
		end
		if spawnedBot.SpeedMultiplier ~= 1 then
			allJoined = false
		end
	end
	check("スポーンしたボットは参加者で、ブロンズなら倍率1", allJoined)

	local body = spawned[1] and spawned[1].Character
	local partNames = {}
	local humanoidOk = false
	if body then
		for _, desc in ipairs(body:GetDescendants()) do
			if desc:IsA("BasePart") then
				partNames[desc.Name] = true
			end
			if desc:IsA("Humanoid") and desc.Health > 0 then
				humanoidOk = true
			end
		end
	end
	local bodyOk = humanoidOk
	for _, partName in ipairs({ "HumanoidRootPart", "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
		if not partNames[partName] then
			bodyOk = false
		end
	end
	check("ボットの体は Humanoid と頭・胴・腕・脚", bodyOk)
	local head = body and body:FindFirstChild("Head")
	local nameGui = head and head:FindFirstChildOfClass("BillboardGui")
	local nameLabel = nameGui and nameGui:FindFirstChild("Label")
	check("頭上にボットの名前が出る", nameLabel ~= nil and nameLabel.Text == "ボット1")

	local headBefore = head and head.Color
	GameState.Taggers = { [spawned[1]] = { Since = 0 } }
	TaggerLook.Apply(spawned[1])
	local tinted = head and head.Color and headBefore
		and not (near(head.Color.G, headBefore.G) and near(head.Color.B, headBefore.B))
	local highlight = body and body:FindFirstChild(TaggerLook.HighlightName)
	check("ボットが鬼になると TaggerLook で赤みと Highlight が付く", tinted and highlight ~= nil)
	TaggerLook.ClearAll()
	GameState.Taggers = {}
	local restored = head and head.Color and headBefore
		and near(head.Color.R, headBefore.R) and near(head.Color.G, headBefore.G) and near(head.Color.B, headBefore.B)
	check("鬼をやめるとボットの色が戻る", restored and body:FindFirstChild(TaggerLook.HighlightName) == nil)

	local tickOk = pcall(function()
		BotManager.Tick()
	end)
	check("経路サービスが無くても思考は直進に倒れて止まらない", tickOk == true)

	calls = {}
	ItemManager.Start()
	ItemManager.SpawnOne()
	local container = RT.workspace:FindFirstChild("SpawnedItems")
	local box = nil
	for _, child in ipairs(container and container:GetChildren() or {}) do
		if child.Name == "ItemBox" then
			box = child
		end
	end
	local arm = body and body:FindFirstChild("Right Arm")
	local lid = box and box:FindFirstChild("Lid")
	if lid and arm and lid.Touched then
		lid.Touched:_Fire(arm)
	end
	local held = GameState.GetData(spawned[1]).HeldItems
	local fromDeck = table.find(Config.DefaultDeck, held[1]) ~= nil
	check("ボットも宝箱に触れるとデッキのアイテムを拾う", box ~= nil and #held == 1 and fromDeck)
	local pickupBotHits = 0
	for _, call in ipairs(calls) do
		if call[2] == spawned[1] then
			pickupBotHits = pickupBotHits + 1
		end
	end
	check("拾ってもボットへは ItemUpdate も Notify も飛ばない", pickupBotHits == 0)
	ItemManager.Stop()

	local keptCharacter = spawned[1].Character
	BotManager.DespawnAll()
	check("ラウンド後はボットが残らない", BotManager.ActiveCount() == 0
		and keptCharacter.Parent == nil
		and RT.workspace:FindFirstChild("Bots") == nil
		and GameState.IsParticipant(spawned[1]) ~= true)

	players.CreateHumanoidModelFromDescription = function()
		local model = RT.Instance.new("Model")
		local root = RT.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2.6, 2, 1.25)
		root.Parent = model
		local humanoid = RT.Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.Parent = model
		return model
	end
	local standardBot = BotManager.Spawn(1)[1]
	players.CreateHumanoidModelFromDescription = createRig
	local rootSize = GameState.GetRootPart(standardBot).Size
	check("太くした標準R15ボットのルートは標準の2×2×1を保つ",
		rootSize.X == 2 and rootSize.Y == 2 and rootSize.Z == 1)
	BotManager.DespawnAll()

	BotManager.Fill({ {} })
	check("人間1人の Fill はボットを出さない", BotManager.ActiveCount() == 0)
	local eight = {}
	for _ = 1, 8 do
		table.insert(eight, {})
	end
	BotManager.Fill(eight)
	check("人間8人の Fill はボットを出さない", BotManager.ActiveCount() == 0)

	local function makeRanked(userId, rp)
		local player = RT.Instance.new("Player")
		player.Name = "Ranked" .. tostring(userId)
		player.UserId = userId
		player.DisplayName = player.Name
		player.Parent = RT.Instance.new("Folder")
		RankManager.Load(player)
		RankManager.Award(player, rp)
		return player
	end
	local masterA = makeRanked(91001, 1300)
	local masterB = makeRanked(91002, 1300)
	BotManager.Fill({ masterA, masterB })
	local strong = BotManager.GetActive()
	local strongOk = #strong == 6
	for _, spawnedBot in ipairs(strong) do
		if spawnedBot.SpeedMultiplier ~= Config.BotSpeedMultiplierCap then
			strongOk = false
		end
		local botHumanoid = spawnedBot.Character and spawnedBot.Character:FindFirstChildOfClass("Humanoid")
		if not botHumanoid or not near(botHumanoid.WalkSpeed, Config.NormalWalkSpeed * Config.BotSpeedMultiplierCap) then
			strongOk = false
		end
	end
	check("人間の平均がマスターなら倍率は上限で、歩く速さに掛かる", strongOk)
	BotManager.DespawnAll()

	GameState.Phase = "Waiting"
	GameState.Taggers = {}
	GameState.Participants = {}
	ZoneManager.Stop()
end

---------------------------------------------------------------------
-- マップ投票
do
	local a, b, c = {}, {}, {}
	local best = RoundManager.TallyMapVotes({ [a] = "Ice", [b] = "Ice", [c] = "Cave" })
	check("マップ投票は一番多いマップ", best == "Ice")
	local tie = RoundManager.TallyMapVotes({ [a] = "Ice", [b] = "Cave" })
	check("同数ならローテーションの次（nil）", tie == nil)
	local none, counts = RoundManager.TallyMapVotes({})
	check("無投票ならローテーションの次（nil）で、全マップの票数0", none == nil and counts.Arena == 0 and counts.Sky == 0)
	local bad = RoundManager.TallyMapVotes({ [a] = "Nowhere" })
	check("知らないマップの票は数えない", bad == nil)
	MapBuilder.ResetRotation({ "Shibuya", "Park", "Cave", "Ice", "Volt", "Sky" }, 1)
	MapBuilder.BuildNextRound()
	check("投票で選んだマップを作る", MapBuilder.PrepareRound("Cave") == true and MapBuilder.CurrentMap == "Cave")
	check("投票のあとは選んだマップからローテーションが続く", MapBuilder.GetNextMapId() == "Ice")
	check("レア度は S・A・B 表記", Config.GetTierName("S") == "S" and Config.Items.TimeStop.Tier == "S"
		and Config.Items.HighJump.Tier == "B")
end

-- 頭の上に乗っているときもタッチ
do
	local runner = { Name = "R" }
	local model = RT.Instance.new("Model")
	local root = RT.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = Vector3.new(3.46, 4.02, 8.88)
	root.Parent = model
	runner.Character = model
	GameState.RegisterCharacter(runner, model)
	check("頭の上に乗った鬼でもタッチになる", RoundManager.IsBodyContact(Vector3.new(3.49, 8.48, 8.29), runner))
	check("離れていればタッチにならない", not RoundManager.IsBodyContact(Vector3.new(12, 4, 8), runner))
	GameState.UnregisterCharacter(model)
end

-- タッチ返しなし
---------------------------------------------------------------------

do
	local a, b, c = { Name = "A" }, { Name = "B" }, { Name = "C" }
	check("タッチしてきた人にはタッチ返しできない", RoundManager.IsTagBackBlocked(a, a) == true)
	check("ほかの人にはタッチできる", RoundManager.IsTagBackBlocked(c, a) == false)
	check("最初の鬼（禁止なし）は誰にでもタッチできる", RoundManager.IsTagBackBlocked(b, nil) == false)
end

---------------------------------------------------------------------

-- ダンジョン固有アイテム・接触・落下の判定
do
	local exclusive = { Cave = "Phase", Ice = "SpikeBoots", Volt = "Insulate", Sky = "SafetyLine" }
	for _, map in ipairs({ "Shibuya", "Park", "Cave", "Ice", "Volt", "Sky" }) do
		local pool = ItemManager.GetFieldPool(Config.DefaultDeck, map)
		local correct = #pool == #Config.DefaultDeck + (exclusive[map] and 1 or 0)
		for _, id in pairs(exclusive) do
			correct = correct and ((table.find(pool, id) ~= nil) == (exclusive[map] == id))
		end
		check(map .. " のフィールド抽選には対応する固有アイテムだけ入る", correct)
	end
	for _, id in pairs(exclusive) do
		local valid = DeckManager.ValidateDeck({ "Dash", "Warp", id })
		check(id .. " はデッキの表示と選択から除外される", not valid and not table.find(Config.ItemOrder, id))
	end
	local buyer = RT.Instance.new("Player")
	buyer.Parent = RT.Instance.new("Folder")
	GameState.Phase = "Round"
	GameState.Participants[buyer] = true
	ItemManager.Start()
	local standardOnly = true
	for _ = 1, 80 do
		local id = ItemManager.GrantItemBox(buyer)
		standardOnly = standardOnly and id ~= nil and Config.Items[id].ExclusiveMap == nil
	end
	check("購入アイテムボックスは通常アイテムだけを付与する", standardOnly)
	GameState.ClearData(buyer)
	GameState.Participants[buyer] = nil
	ItemManager.Stop()

	local slide = Config.IceVelocity(Vector3.new(16, 0, 0), Vector3.new(0, 0, 0), 16, 0.2)
	check("氷床で入力を離すと水平速度が減衰して残る", slide.X > 0 and slide.X < 16)
	local turn = Config.IceVelocity(Vector3.new(16, 0, 0), Vector3.new(0, 0, 1), 16, 0.2)
	check("氷床で曲がると元の方向の速度が残りつつ新しい方向へ進む", turn.X > 0 and turn.Z > 0)

	local function makePlayer(id, isBot)
		local player = isBot and { IsBot = true } or RT.Instance.new("Player")
		player.UserId = id
		player.DisplayName = "Dungeon " .. id
		local character = RT.Instance.new("Model")
		character.Parent = RT.workspace
		player.Character = character
		local root = RT.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Position = Vector3.new(0, 4, 0)
		root.CFrame = RT.CFrame.new(0, 4, 0)
		root.Color = Color3.fromRGB(80, 90, 100)
		root.Parent = character
		local humanoid = RT.Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.JumpPower = 50
		humanoid.JumpHeight = 7
		humanoid.FloorMaterial = RT.Enum.Material.Slate
		humanoid.Parent = character
		GameState.Participants[player] = true
		GameState.RegisterCharacter(player, character)
		return player, root, humanoid
	end

	local now = 100
	local realNow = GameState.Now
	GameState.Now = function() return now end
	GameState.Phase = "Round"
	ItemManager.Start()
	local player, root, humanoid = makePlayer(15000, false)
	local bot, botRoot, botHumanoid = makePlayer(-15000, true)
	local data = GameState.GetData(player)
	local function give(id)
		data.HeldItems = { id }
		data.HeldExpireAt = { 0 }
	end
	MapBuilder.ResetRotation(MapBuilder.AllMaps, 1)
	local function advanceTo(id)
		repeat
			MapBuilder.BuildNextRound()
		until MapBuilder.CurrentMap == id
		return RT.workspace:FindFirstChild(MapBuilder.MapFolderName)
	end

	local cave = advanceTo("Cave")
	local wall = cave:FindFirstChild("CaveInnerWalls"):GetChildren()[1]
	local physics = RT.game:GetService("PhysicsService")
	check("壁抜けグループは洞窟内壁だけと非衝突",
		not physics:CollisionGroupsAreCollidable(wall.CollisionGroup, MapBuilder.PhaseGroup)
		and physics:CollisionGroupsAreCollidable("Default", MapBuilder.PhaseGroup))
	root.CollisionGroup = "AvatarOriginal"
	give("Phase")
	ItemManager.TryUse(player, 1)
	check("壁抜けを使うと2.5秒の効果と衝突グループが適用される",
		near(data.PhaseUntil, now + 2.5) and root.CollisionGroup == MapBuilder.PhaseGroup and #data.HeldItems == 0)
	root.Position = Vector3.new(15, 4, 15)
	RT.workspace._overlap = function(part, params)
		assert(params.FilterDescendantsInstances[1] == wall.Parent)
		return part == root and { wall } or {}
	end
	now += 2.5
	ItemManager.Tick()
	check("内壁にめり込んでいたら使用開始位置へ戻る", root.Position.X == 0 and root.Position.Z == 0)
	check("壁抜け終了で元の衝突グループに戻る", data.PhaseUntil == 0 and root.CollisionGroup == "AvatarOriginal")
	RT.workspace._overlap = nil

	advanceTo("Ice")
	give("SpikeBoots")
	ItemManager.TryUse(player, 1)
	check("スパイクブーツの効果は5秒間", near(data.SpikeBootsUntil, now + 5) and #data.HeldItems == 0)

	local volt = advanceTo("Volt")
	local hazard = volt:FindFirstChild("VoltHazard")
	GameState.Taggers = { [bot] = { Since = now } }
	hazard.Touched:_Fire(root)
	hazard.Touched:_Fire(botRoot)
	check("帯電部品との接触で人間と鬼ボットが痺れる",
		near(data.StunUntil, now + 1.2) and GameState.IsStunned(bot)
		and humanoid.WalkSpeed == 0 and humanoid.JumpHeight == 0
		and botHumanoid.WalkSpeed == 0)
	now += 1.2
	ItemManager.Tick()
	check("痺れの終了で速度とジャンプが戻る", data.StunUntil == 0 and humanoid.WalkSpeed == Config.NormalWalkSpeed
		and near(humanoid.JumpHeight, Config.NormalJumpHeight))
	now += 1.9
	hazard.Touched:_Fire(root)
	check("痺れの終了後2秒間は再発しない", data.StunUntil == 0)
	now += 0.2
	give("Insulate")
	ItemManager.TryUse(player, 1)
	hazard.Touched:_Fire(root)
	check("絶縁の6秒間は痺れない", near(data.InsulateUntil, now + 6) and data.StunUntil == 0)
	hazard.Touched:_Fire(botRoot)
	check("回復時間が過ぎたら再び痺れる", near(GameState.GetData(bot).StunUntil, now + 1.2))
	now += 6
	hazard.Touched:_Fire(root)
	check("絶縁の期限が過ぎると再び痺れる", near(data.StunUntil, now + 1.2))
	now += 1.2
	ItemManager.Tick()

	advanceTo("Ice")
	local owner = makePlayer(1461, false)
	GameState.Participants[owner] = true
	local ownerData = GameState.GetData(owner)
	for _, victim in ipairs({ player, bot }) do
		ownerData.HeldItems = { "Banana" }
		ownerData.HeldExpireAt = { 0 }
		ItemManager.TryUse(owner, 1)
		local trap = RT.workspace:FindFirstChild("SpawnedItems"):FindFirstChild("BananaTrap")
		local victimRoot = GameState.GetRootPart(victim)
		local victimHumanoid = GameState.GetHumanoid(victim)
		local victimData = GameState.GetData(victim)
		local states = RT.Enum.HumanoidStateType
		trap.Touched:_Fire(GameState.GetRootPart(owner))
		check("バナナは置いた本人に効かない", not GameState.IsDowned(owner))
		victimRoot.AssemblyLinearVelocity = Vector3.new(10, 4, 8)
		trap.Touched:_Fire(victimRoot)
		victimData.HeldItems = { "Dash" }
		victimData.HeldExpireAt = { 0 }
		ItemManager.TryUse(victim, 1)
		check("バナナを踏むと転倒し、移動・ジャンプ・アイテム使用が止まる",
			Config.Items.Banana.DownTime == 1.5 and near(victimData.DownUntil, now + 1.5)
			and GameState.IsDowned(victim) and victimHumanoid:GetState() == states.FallingDown
			and not victimHumanoid:GetStateEnabled(states.GettingUp)
			and victimHumanoid.WalkSpeed == 0 and victimHumanoid.JumpHeight == 0
			and victimRoot.AssemblyLinearVelocity.Magnitude == 0 and victimData.HeldItems[1] == "Dash")
		check("バナナの滑り効果は残らない",
			victimData.SlipUntil == nil and Config.Items.Banana.SlipTime == nil
			and victim.Character:GetAttribute("BananaSlipping") == nil)
		now += 1.5
		ItemManager.Tick()
		check("転倒時間が過ぎると起き上がり移動とジャンプが戻る",
			not GameState.IsDowned(victim) and victimData.DownUntil == 0
			and victimHumanoid:GetState() == states.GettingUp and victimHumanoid:GetStateEnabled(states.GettingUp)
			and victimHumanoid.WalkSpeed > 0 and victimHumanoid.JumpHeight == Config.NormalJumpHeight)
	end
	GameState.Participants[owner] = nil
	GameState.UnregisterCharacter(owner.Character)
	GameState.ClearData(owner)
	owner.Character:Destroy()

	local sky = advanceTo("Sky")
	root.Position = Vector3.new(7, 54, 8)
	botRoot.Position = Vector3.new(0, 54, 0)
	RT.workspace._raycast = function(_, _, params)
		return { Instance = params.FilterDescendantsInstances[1]:FindFirstChild("ArenaStart") }
	end
	RoundManager.CheckSkyFalls()
	RT.workspace._raycast = nil
	check("立っていた足場を復帰先として記録する", data.LastSkyStand and data.LastSkyStand.Position.X == 7)
	data.HeldItems = { "Dash", "SafetyLine" }
	data.HeldExpireAt = { now + 15, 0 }
	root.Position = Vector3.new(0, Config.FallEliminateY, 0)
	RoundManager.CheckSkyFalls()
	check("落下しきい値と同じ高さでは命綱を消費しない", #data.HeldItems == 2)
	root.Position = Vector3.new(0, Config.FallEliminateY - 1, 0)
	RoundManager.CheckSkyFalls()
	check("落下時に命綱で足場へ戻り、命綱だけが消費される", GameState.IsParticipant(player)
		and root.Position.X == 7 and root.Position.Y == 54 and #data.HeldItems == 1
		and data.HeldItems[1] == "Dash" and #data.HeldExpireAt == 1 and data.HeldExpireAt[1] == now + 15)
	local botData = GameState.GetData(bot)
	botData.HeldItems = { "SafetyLine" }
	botData.HeldExpireAt = { 0 }
	GameState.Taggers = { [bot] = { Since = now } }
	botRoot.Position = Vector3.new(0, Config.FallEliminateY - 1, 0)
	RoundManager.CheckSkyFalls()
	check("鬼ボットは命綱を使わず、落下脱落しても最後の逃げ役はそのまま",
		not GameState.IsParticipant(bot) and table.find(GameState.Eliminated, bot) ~= nil
		and #botData.HeldItems == 1 and not GameState.IsTagger(player))
	root.Position = Vector3.new(0, Config.FallEliminateY - 1, 0)
	GameState.Uncaught[player] = true
	RoundManager.CheckSkyFalls()
	check("命綱は一度限りで、次の落下では脱落して観戦位置へ移る",
		not GameState.IsParticipant(player) and table.find(GameState.Eliminated, player) ~= nil
		and GameState.Uncaught[player] == nil and root.Position.Y > sky:FindFirstChild("PlayerSpawn").Position.Y
		and next(GameState.Taggers) == nil)

	TaggerLook.ClearAll()
	ItemManager.Stop()
	for _, entity in ipairs({ player, bot }) do
		GameState.UnregisterCharacter(entity.Character)
		GameState.ClearData(entity)
		entity.Character:Destroy()
	end
	GameState.Eliminated = {}
	GameState.Uncaught = {}
	GameState.Now = realNow
	GameState.Phase = "Waiting"
end

---------------------------------------------------------------------
-- タッチ判定：パーツの表面と既存の交代条件
---------------------------------------------------------------------

do
	local CFrame = RT.CFrame
	local now = 100
	local realNow = GameState.Now
	GameState.Now = function() return now end
	GameState.Phase = "Round"

	local function place(part, pose)
		part.CFrame = pose
		part.Position = pose.Position
	end

	local function makePlayer(id, pose)
		local player = RT.Instance.new("Player")
		player.UserId = id
		player.DisplayName = "Tag test " .. id
		local character = RT.Instance.new("Model")
		player.Character = character
		local root = RT.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		place(root, pose)
		root.Parent = character
		local humanoid = RT.Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.Parent = character
		return player, root
	end

	local tagger, taggerRoot = makePlayer(16001, CFrame.new(0, 0, 0))
	local runner, runnerRoot = makePlayer(16002, CFrame.new(0, 0, -6) * CFrame.Angles(0, math.pi, 0))
	local data = GameState.GetData(runner)
	local function resetTagger(target)
		GameState.Participants = { [tagger] = true, [target] = true }
		GameState.Taggers = { [tagger] = { Since = now } }
		GameState.Taggers[tagger].Since = now - Config.TagCooldown
		GameState.Uncaught = {}
	end
	local function tryTag(target)
		RoundManager.TryTag()
		return GameState.IsTagger(target)
	end

	local arm = RT.Instance.new("Part")
	arm.Name = "Arm"
	place(arm, CFrame.new(0, 0, -3.25))
	arm.Parent = runner.Character
	resetTagger(runner)
	local taggerRP = RankManager.Get(tagger).RP
	local runnerRP = RankManager.Get(runner).RP
	local taggedCount = RankManager.Get(runner).Tagged
	check("正面から腕に届けば中心間が旧しきい値の5スタッドを超えても交代する",
		(runnerRoot.Position - taggerRoot.Position).Magnitude > 5 and tryTag(runner))
	check("タッチでRPと回数が加算され、新しい鬼のクールダウンが始まる",
		RankManager.Get(tagger).RP == taggerRP + Config.RankPoints.Tag
		and RankManager.Get(runner).RP == runnerRP + Config.RankPoints.Caught
		and RankManager.Get(runner).Tagged == taggedCount + 1
		and GameState.Taggers[runner].Since == now)
	check("タッチした側と捕まった側の属性はそれぞれの回数と付与RPに一致する",
		tagger:GetAttribute("RoundTags") == 1 and tagger:GetAttribute("RoundCaught") == nil
		and tagger:GetAttribute("RoundRP") == RankManager.Get(tagger).RP - taggerRP
		and runner:GetAttribute("RoundTags") == nil and runner:GetAttribute("RoundCaught") == 1
		and runner:GetAttribute("RoundRP") == RankManager.Get(runner).RP - runnerRP)
	arm:Destroy()

	local accessory = RT.Instance.new("Accessory")
	accessory.Parent = runner.Character
	local handle = RT.Instance.new("MeshPart")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 3)
	handle.Parent = accessory
	place(handle, CFrame.new(2.7, 0, -1.6))
	resetTagger(runner)
	check("横のアクセサリは表面が届かなければ交代しない", not tryTag(runner))
	place(handle, CFrame.new(2.7, 0, -1.6) * CFrame.Angles(0, math.pi / 2, 0))
	check("横のアクセサリは回転して表面が届けば交代する", tryTag(runner))
	accessory:Destroy()

	resetTagger(runner)
	RT.Instance.new("ForceField").Parent = runner.Character
	check("相手のパーツが離れていればForceFieldがあっても交代しない", not tryTag(runner))
	place(runnerRoot, CFrame.new(0, 0, -3))
	check("相手の背後からでも表面が届けば交代する", tryTag(runner))

	resetTagger(runner)
	GameState.Taggers[tagger].Since = now
	check("鬼になった直後は手が届いても交代しない", not tryTag(runner))
	GameState.Taggers[tagger].Since = now - Config.TagCooldown
	data.StarUntil = now + 1
	data.ShieldUntil = now + 5
	check("スター中はタッチが無効でシールドも残る", not tryTag(runner) and data.ShieldUntil == now + 5)
	data.StarUntil = 0
	check("シールドがタッチを防ぎ、無敵時間が始まる", not tryTag(runner)
		and data.ShieldUntil == 0 and data.InvulnerableUntil == now + Config.Items.Shield.GraceTime)
	check("シールド後の無敵中は手が届いても交代しない", not tryTag(runner))
	now = data.InvulnerableUntil
	check("無敵終了後は届いていれば交代する", tryTag(runner))

	BotManager.Fill({ tagger, runner })
	local bot = BotManager.GetActive()[1]
	local botRoot = GameState.GetRootPart(bot)
	local botArm = bot.Character:FindFirstChild("Right Arm")
	-- ボットの右腕の横から、腕だけに届く位置でタッチする。
	local armPosition = botArm.Position
	place(taggerRoot, CFrame.new(armPosition.X + 3.2, armPosition.Y, armPosition.Z)
		* CFrame.Angles(0, math.pi / 2, 0))
	resetTagger(bot)
	check("生成したボットの腕に届けば鬼が交代する",
		(botRoot.Position - taggerRoot.Position).Magnitude > Config.TagReachForward + Config.TagTouchDistance
		and tryTag(bot))

	check("捕まったボットにはラウンド属性を作らない",
		bot.GetAttribute == nil and bot.RoundTags == nil and bot.RoundCaught == nil and bot.RoundRP == nil)

	-- 実際の選出から、別々の鬼が逃げ役を1人ずつ捕まえるまでを確認する。
	local extraA = makePlayer(16003, CFrame.new(0, 0, 0))
	local extraB = makePlayer(16004, CFrame.new(0, 0, 0))
	GameState.Taggers = {}
	TaggerLook.ClearAll()
	GameState.Participants = { [tagger] = true }
	RoundManager.SelectInitialTaggers()
	check("参加者が1人なら鬼は1人", #GameState.TaggerList() == 1)
	GameState.Taggers = {}
	TaggerLook.ClearAll()
	GameState.Participants[runner] = true
	RoundManager.SelectInitialTaggers()
	check("参加者が2人なら鬼は1人", #GameState.TaggerList() == 1)
	GameState.Taggers = {}
	TaggerLook.ClearAll()
	GameState.Participants[extraA] = true
	GameState.Participants[extraB] = true
	RoundManager.SelectInitialTaggers()
	local initial = GameState.TaggerList()
	local runners = {}
	for _, player in ipairs(GameState.ParticipantList()) do
		GameState.ResetData(player)
		if not GameState.IsTagger(player) then
			table.insert(runners, player)
		end
	end
	check("参加者が4人なら2人を鬼に選び、両方を赤くする",
		Config.TaggerCount == 2 and #initial == 2 and #runners == 2
		and initial[1].Character:FindFirstChild(TaggerLook.HighlightName) ~= nil
		and initial[2].Character:FindFirstChild(TaggerLook.HighlightName) ~= nil)
	place(GameState.GetRootPart(initial[1]), CFrame.new(0, 0, 0))
	place(GameState.GetRootPart(initial[2]), CFrame.new(40, 0, 0))
	place(GameState.GetRootPart(runners[1]), CFrame.new(0, 0, -2))
	place(GameState.GetRootPart(runners[2]), CFrame.new(40, 0, -2))
	local firstRP, lastRP = RankManager.Get(initial[1]).RP, RankManager.Get(initial[2]).RP
	now += Config.TagCooldown
	RoundManager.TryTag()
	check("2人の鬼は独立して捕まえ、全員捕獲RPは最後の鬼だけに入る",
		GameState.IsTagger(runners[1]) and GameState.IsTagger(runners[2]) and #GameState.TaggerList() == 2
		and GameState.Taggers[runners[1]].NoTagBack == initial[1]
		and GameState.Taggers[runners[2]].NoTagBack == initial[2]
		and RankManager.Get(initial[1]).RP == firstRP + Config.RankPoints.Tag
		and RankManager.Get(initial[2]).RP == lastRP + Config.RankPoints.Tag + Config.RankPoints.TaggedAll)
	local currentTagger = runners[1]
	local role = GameState.Taggers[currentTagger]
	local since, noTagBack = role.Since, role.NoTagBack
	local highlight = currentTagger.Character:FindFirstChild(TaggerLook.HighlightName)
	now += 1
	check("すでに鬼の人への管理指定はクールダウン・タッチ返し禁止・見た目を保つ",
		RoundManager.SetAdminTagger(currentTagger) and GameState.Taggers[currentTagger] == role
		and role.Since == since and role.NoTagBack == noTagBack
		and currentTagger.Character:FindFirstChild(TaggerLook.HighlightName) == highlight)

	local players = RT.game:GetService("Players")
	RoundManager.Init()
	TaggerLook.ClearAll()
	GameState.Taggers = {}
	RoundManager.SelectInitialTaggers()
	local taggers = GameState.TaggerList()
	local departing, remaining
	for _, player in ipairs(GameState.ParticipantList()) do
		if GameState.Uncaught[player] then
			if departing then
				remaining = player
			else
				departing = player
			end
		end
	end
	players.PlayerRemoving:_Fire(departing)
	place(GameState.GetRootPart(taggers[1]), CFrame.new(0, 0, 0))
	place(GameState.GetRootPart(taggers[2]), CFrame.new(40, 0, 0))
	place(GameState.GetRootPart(remaining), CFrame.new(0, 0, -2))
	local beforeCapture = RankManager.Get(taggers[1]).RP
	now += Config.TagCooldown
	RoundManager.TryTag()
	check("退出した未捕獲者を除いた最後のタッチで全員捕獲RP +14 が入る",
		not GameState.IsParticipant(departing) and next(GameState.Uncaught) == nil
		and RankManager.Get(taggers[1]).RP == beforeCapture + Config.RankPoints.Tag + 14)

	local roster = { tagger, runner, extraA }
	local getPlayers, wait = players.GetPlayers, RT.task.wait
	local botsEnabled = Config.BotsEnabled
	Config.BotsEnabled = false
	players.GetPlayers = function() return roster end
	RT.task.wait = function(seconds) coroutine.yield(seconds) end
	for _, player in ipairs(roster) do
		player.Parent = players
		player.LoadCharacter = function() end
	end
	GameState.Phase = "Waiting"
	GameState.Taggers = {}
	TaggerLook.ClearAll()
	MapBuilder.BuildMap("Cave")
	local function stepRound(round)
		local ok, delay = coroutine.resume(round)
		assert(ok, debug.traceback(round, tostring(delay)))
		now += delay
	end
	local function startTestRound()
		local round = coroutine.create(RoundManager.Run)
		for _ = 1, Config.IntermissionTime + 2 do
			stepRound(round)
			if GameState.Phase == "Round" then
				return round
			end
		end
		error("テストのラウンドが始まらなかった")
	end
	local round = startTestRound()
	local originalTaggers = GameState.TaggerList()
	local lastRunner = next(GameState.Uncaught)
	assert(GameState.Phase == "Round" and #originalTaggers == 2 and lastRunner)
	-- 次のゾーン更新で、唯一の開始時の逃げ役をエリア外で脱落させる。
	place(GameState.GetRootPart(lastRunner), CFrame.new(500, 0, 500))
	local lastRunnerData = GameState.GetData(lastRunner)
	lastRunnerData.ZoneStamina = 0
	lastRunnerData.ZoneReturns = Config.ZoneMaxReturns
	now += Config.TagCooldown
	stepRound(round)
	check("鬼2人と逃げ役1人で逃げ役が脱落すると、その場で鬼の勝ちになる",
		GameState.Phase == "Results" and GameState.Message == "鬼の勝ち！"
		and #GameState.Winners == 0 and next(GameState.Uncaught) == nil
		and GameState.Results[1].Status == "最後の鬼" and GameState.Results[2].Status == "最後の鬼"
		and originalTaggers[1]:GetAttribute("RoundRP") == 0
		and originalTaggers[2]:GetAttribute("RoundRP") == 0)
	round = startTestRound()
	local formerTagger = GameState.TaggerList()[1]
	lastRunner = next(GameState.Uncaught)
	assert(RoundManager.SetAdminTagger(lastRunner) and not GameState.IsTagger(formerTagger))
	now += GameState.ChosenDuration
	stepRound(round)
	check("管理指定で逃げ役に戻った元の鬼は時間切れでも優勝・生存RPを得ない",
		GameState.Phase == "Results" and #GameState.Winners == 0
		and GameState.Results[1].UserId == formerTagger.UserId and GameState.Results[1].Status ~= "優勝"
		and formerTagger:GetAttribute("RoundRP") == 0)

	players.GetPlayers, RT.task.wait = getPlayers, wait
	Config.BotsEnabled = botsEnabled
	for _, player in ipairs(roster) do
		player.Parent = nil
	end
	GameState.Eliminated = {}

	for _, player in ipairs({ extraA, extraB }) do
		GameState.ClearData(player)
		player.Character:Destroy()
	end

	TaggerLook.ClearAll()
	BotManager.DespawnAll()
	for _, player in ipairs({ tagger, runner }) do
		GameState.ClearData(player)
		player.Character:Destroy()
	end
	GameState.Participants = {}
	GameState.Uncaught = {}
	GameState.Taggers = {}
	GameState.Now = realNow
	GameState.Phase = "Waiting"
end



do
	local player = RT.Instance.new("Player")
	player.Character = RT.Instance.new("Model")
	player.Character:SetAttribute("BananaDowned", true)
	GameState.ClearDown(player)
	check("Humanoid や転倒タイマーがなくても BananaDowned が消える",
		player.Character:GetAttribute("BananaDowned") == nil)
	GameState.ClearData(player)
end


do
	local arenaFixture = require("./.build/ArenaFixture")
	for _, name in ipairs({ "Map", "ItemSpawns" }) do
		local existing = RT.workspace:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
		local folder = RT.Instance.new("Folder")
		folder.Name = name
		for _, spec in ipairs(arenaFixture[name]) do
			local partName, className, position, size = table.unpack(spec)
			local part = RT.Instance.new(className)
			part.Name = partName
			part.Position = Vector3.new(table.unpack(position))
			part.Size = Vector3.new(table.unpack(size))
			part.Parent = folder
		end
		folder.Parent = RT.workspace
	end
	check("アリーナの実データをテンプレートにする", MapBuilder.StashArena())
	for _, id in ipairs(MapBuilder.AllMaps) do
		local summary = MapBuilder.BuildMap(id)
		local map = RT.workspace:FindFirstChild("Map")
		ZoneManager.Start(180)
		local covered = summary.MapId == id
		local points, fallback = ItemManager.GetSpawnPoints()
		covered = covered and not fallback
		for _, point in ipairs(points) do
			covered = covered and ZoneManager.IsInside(point.Position)
		end
		for _, part in ipairs(map:GetDescendants()) do
			if part:IsA("SpawnLocation") then
				covered = covered and ZoneManager.IsInside(part.Position)
			end
		end
		local surfaceName = ({ Arena = "Floor", Shibuya = "Base", Park = "Grass", Cave = "StoneFloor",
			Ice = "IceFloor", Volt = "MetalFloor" })[id]
		local surfaces = surfaceName and { assert(map:FindFirstChild(surfaceName, true)) }
			or map:FindFirstChild("SkyPlatforms"):GetChildren()
		for _, surface in ipairs(surfaces) do
			for _, x in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					local corner = surface.Position + Vector3.new(x * surface.Size.X / 2, 0, z * surface.Size.Z / 2)
					covered = covered and ZoneManager.IsInside(corner)
				end
			end
		end
		check(id .. " の出現点と床の四隅が開始ゾーン内にある", covered)
		ZoneManager.Stop()
	end
end


---------------------------------------------------------------------
-- デイリールーレット（30分ごとに権利がたまる）
---------------------------------------------------------------------

do
	local rules = Config.Roulette
	local base = 1000000
	local fresh = PlayerDataStore.Normalize(nil)
	check("ルーレット：新しいデータは未開始", fresh.RouletteStock == 0 and fresh.RouletteAt == 0)
	PlayerDataStore.AccrueRoulette(fresh, base)
	check("ルーレット：初めての人は最初から1回まわせる", fresh.RouletteStock == rules.StartStock and fresh.RouletteAt == base)
	PlayerDataStore.AccrueRoulette(fresh, base + rules.Interval - 1)
	check("ルーレット：30分たつ前は増えない", fresh.RouletteStock == 1)
	PlayerDataStore.AccrueRoulette(fresh, base + rules.Interval)
	check("ルーレット：30分で1回増える", fresh.RouletteStock == 2 and fresh.RouletteAt == base + rules.Interval)
	PlayerDataStore.AccrueRoulette(fresh, base + rules.Interval * 10)
	check("ルーレット：何時間たっても上限まで", fresh.RouletteStock == rules.MaxStock)
	check("ルーレット：満タンのあいだは時間をためない", fresh.RouletteAt == base + rules.Interval * 10)
	local stock, nextIn = PlayerDataStore.RouletteView(fresh, base + rules.Interval * 10)
	check("ルーレット：満タンなら次の時間は出さない", stock == rules.MaxStock and nextIn == nil)

	local viewer = { UserId = 19005 }
	local viewed = PlayerDataStore.Load(viewer)
	local allStocksMatch = viewed.RouletteAt == 0
	for step = 0, rules.MaxStock - rules.StartStock do
		local at = base + step * rules.Interval
		local shown, seconds = PlayerDataStore.RouletteView(viewed, at)
		local expected = rules.StartStock + step
		allStocksMatch = allStocksMatch and shown == expected and viewed.RouletteAt == at
			and (expected == rules.MaxStock and seconds == nil or seconds == rules.Interval)
	end
	check("ルーレット：初回の表示から使わずに上限までたまる", allStocksMatch)
	local spunFromView, afterView = PlayerDataStore.SpinRoulette(viewer, 1, viewed.RouletteAt)
	check("ルーレット：初回の保存でも表示でたまった回数を使える",
		spunFromView and afterView.RouletteStock == rules.MaxStock - 1 and afterView.RouletteAt == viewed.RouletteAt)
	PlayerDataStore.Forget(viewer)

	local kept = PlayerDataStore.Normalize({ Coins = 5, RouletteStock = 2, RouletteAt = 1234 })
	check("ルーレット：保存データの回数と時刻は Normalize で消えない", kept.RouletteStock == 2 and kept.RouletteAt == 1234)
	local capped = PlayerDataStore.Normalize({ RouletteStock = 99 })
	check("ルーレット：壊れた回数は上限に直る", capped.RouletteStock == rules.MaxStock)

	check("ルーレット：抽選の最初と最後", PlayerDataStore.PickRoulettePrize(0) == 1
		and PlayerDataStore.PickRoulettePrize(0.9999) == #rules.Prizes)

	local spinner = RT.Instance.new("Player")
	spinner.Name = "Spinner"
	spinner.UserId = 777
	PlayerDataStore.Load(spinner)
	local ok1, after1 = PlayerDataStore.SpinRoulette(spinner, 4, base)
	check("ルーレット：1回目はまわせて景品のコインが入る", ok1 == true
		and after1.Coins == rules.Prizes[4].Coins and after1.RouletteStock == 0)
	local ok2 = PlayerDataStore.SpinRoulette(spinner, 1, base + 60)
	check("ルーレット：権利がないとまわせない", ok2 == false and PlayerDataStore.Get(spinner).Coins == rules.Prizes[4].Coins)
	local _, nextAfterSpin = PlayerDataStore.RouletteView(PlayerDataStore.Get(spinner), base + 60)
	check("ルーレット：次の1回までの残り秒", nextAfterSpin == rules.Interval - 60)
	local ok3, after3 = PlayerDataStore.SpinRoulette(spinner, 1, base + rules.Interval)
	check("ルーレット：30分後にまたまわせる", ok3 == true and after3.Coins == rules.Prizes[4].Coins + rules.Prizes[1].Coins)
	local afterCoins = PlayerDataStore.AddCoins(spinner, 10, false)
	check("ルーレット：試合のコイン加算でも回数と時刻が残る", afterCoins.RouletteAt == base + rules.Interval)
	check("ルーレット：景品の番号が不正なら何もしない", PlayerDataStore.SpinRoulette(spinner, 99, base) == false)
end

---------------------------------------------------------------------
-- 召喚獣：抽選・保存・モデル・実際の ItemManager / ZoneManager の効果
---------------------------------------------------------------------

do
	local bands = {
		{ 0, 15, "Bastet", "B" }, { 15, 30, "Thoth", "B" },
		{ 30, 45, "Khepri", "B" }, { 45, 60, "Hathor", "B" },
		{ 60, 68, "Sobek", "A" }, { 68, 76, "Sekhmet", "A" }, { 76, 84, "Isis", "A" },
		{ 84, 88, "Horus", "S" }, { 88, 92, "Osiris", "S" }, { 92, 96, "Set", "S" },
		{ 96, 98, "Anubis", "SS" }, { 98, 100, "Ra", "SS" },
	}
	local definitionCount = 0
	for _ in pairs(Config.Beasts) do
		definitionCount += 1
	end
	local totalWeight = 0
	for _, id in ipairs(Config.BeastOrder) do
		totalWeight += Config.Beasts[id].Weight
	end
	check("召喚獣は12体で抽選確率の合計は100%", definitionCount == 12 and #Config.BeastOrder == 12 and totalWeight == 100)
	for _, band in ipairs(bands) do
		local low, high, id, tier = band[1], band[2], band[3], band[4]
		local def = Config.Beasts[id]
		check(id .. " のレア度と抽選帯", def and def.Tier == tier and def.Weight == high - low
			and PlayerDataStore.PickBeast(low / 100) == id and PlayerDataStore.PickBeast((high - 0.001) / 100) == id)
		local model = RT.modules.BeastModels.Build(id, RT.CFrame.new(), 0.4)
		local blocks = model:GetChildren()
		local decorative = #blocks > 0
		for _, block in ipairs(blocks) do
			decorative = decorative and block.Anchored and not block.CanCollide and not block.CanTouch and not block.CanQuery
		end
		check(id .. " のブロックは固定され、判定に影響しない", decorative)
		model:Destroy()
	end

	local old = PlayerDataStore.Normalize({ Coins = 99 })
	check("旧データは召喚獣なしで読み込める", next(old.Beasts) == nil and old.EquippedBeast == nil)
	local clean = PlayerDataStore.Normalize({
		Beasts = { Bastet = true, Thoth = false, Unknown = true },
		EquippedBeast = "Bastet",
	})
	check("Normalize は正しい所持と装備を残す",
		clean.Beasts.Bastet and not clean.Beasts.Thoth and not clean.Beasts.Unknown and clean.EquippedBeast == "Bastet")
	check("Normalize は未所持の装備を解除する",
		PlayerDataStore.Normalize({ Beasts = { Bastet = true }, EquippedBeast = "Thoth" }).EquippedBeast == nil)

	local store = RT.game:GetService("DataStoreService"):GetDataStore("PlayerData_v1")
	local player = { UserId = 19000 }
	store:SetAsync("u_19000", { Coins = 99 })
	PlayerDataStore.Load(player)
	local result, _, data = PlayerDataStore.DrawBeast(player)
	check("99コインでは抽選できず、残高も所持も変わらない", not result and data.Coins == 99 and next(data.Beasts) == nil)
	check("未所持の召喚獣は装備できない", not PlayerDataStore.SetEquippedBeast(player, "Bastet"))

	PlayerDataStore.AddCoins(player, 101, false)
	result, _, data = PlayerDataStore.DrawBeast(player)
	check("ガチャ1回で100コイン減り、召喚獣を獲得する", result and not result.Duplicate and data.Coins == 100 and data.Beasts[result.Id])
	check("所持している召喚獣を装備できる", PlayerDataStore.SetEquippedBeast(player, result.Id))
	local returningPlayer = { UserId = player.UserId }
	local loaded = PlayerDataStore.Load(returningPlayer)
	check("獲得と装備の両方が再読み込みで復元される",
		loaded.Coins == 100 and loaded.Beasts[result.Id] and loaded.EquippedBeast == result.Id)
	PlayerDataStore.Forget(returningPlayer)

	local spun = PlayerDataStore.SpinRoulette(player, 4, 1000000)
	local nextBeast, _, afterDraw = PlayerDataStore.DrawBeast(player)
	local afterBoth = PlayerDataStore.Load(returningPlayer)
	check("同じ保存データでルーレットを回してガチャを引いても、回数・時刻・所持・装備が残る",
		spun and nextBeast and afterBoth.RouletteStock == 0 and afterBoth.RouletteAt == 1000000
		and afterBoth.Beasts[nextBeast.Id] and afterBoth.Beasts[result.Id] and afterBoth.EquippedBeast == result.Id
		and afterBoth.Coins == afterDraw.Coins)
	PlayerDataStore.Forget(returningPlayer)

	local owned = {}
	for _, id in ipairs(Config.BeastOrder) do
		owned[id] = true
	end
	store:SetAsync("u_19000", { Coins = 100, Beasts = owned, EquippedBeast = "Anubis" })
	PlayerDataStore.Load(player)
	result, _, data = PlayerDataStore.DrawBeast(player)
	check("重複時は40コイン返却され、装備は保持される",
		result and result.Duplicate and data.Coins == 40 and data.EquippedBeast == "Anubis")
	PlayerDataStore.Forget(player)
end

do
	local store = RT.game:GetService("DataStoreService"):GetDataStore("PlayerData_v1")
	local player = { UserId = 19006 }
	local now = 1000000
	local coins = Config.BeastDrawCost * 2
	store:SetAsync("u_19006", {
		Coins = coins, Beasts = { Bastet = true, Anubis = true }, EquippedBeast = "Anubis",
		RouletteAt = now, RouletteStock = 2,
	})
	local original = PlayerDataStore.Load(player)
	RT.DataStoreShouldFail = true
	local result, drawReason = PlayerDataStore.DrawBeast(player)
	local equipped, _, equipReason = PlayerDataStore.SetEquippedBeast(player, "Bastet")
	local spun, _, spinReason = PlayerDataStore.SpinRoulette(player, 4, now + Config.Roulette.Interval)
	RT.DataStoreShouldFail = false

	local cached = PlayerDataStore.Get(player)
	local function unchanged(data)
		local ownedCount = 0
		for _ in pairs(data.Beasts) do
			ownedCount += 1
		end
		return data.Coins == coins and data.RouletteStock == 2 and data.RouletteAt == now
			and data.EquippedBeast == "Anubis" and ownedCount == 2 and data.Beasts.Bastet and data.Beasts.Anubis
	end
	check("保存失敗：ガチャ・装備・ルーレットが失敗理由を返す",
		result == nil and drawReason and not equipped and equipReason and not spun and spinReason)
	check("保存失敗：キャッシュと保存済みの残高・権利・所持・装備を保持する",
		cached == original and unchanged(cached) and unchanged(PlayerDataStore.Load(player)))
	PlayerDataStore.Forget(player)
end

do
	local players = RT.game:GetService("Players")
	local store = RT.game:GetService("DataStoreService"):GetDataStore("PlayerData_v1")
	local function entrant(id, x)
		local player = RT.Instance.new("Player")
		player.UserId = id
		player.DisplayName = "Summon " .. id
		player.Parent = players
		local character = RT.Instance.new("Model")
		character.Parent = RT.workspace
		player.Character = character
		local root = RT.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Position = Vector3.new(x, 4, 0)
		root.CFrame = RT.CFrame.new(root.Position)
		root.Parent = character
		local humanoid = RT.Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.Parent = character
		GameState.Participants[player] = true
		GameState.RefreshSpeed(player)
		return player, root, humanoid
	end

	local realNow = GameState.Now
	local now = 100
	GameState.Now = function() return now end
	GameState.Phase = "Round"
	local player, root, humanoid = entrant(19001, 0)
	local enemy, enemyRoot, enemyHumanoid = entrant(19002, 4)
	local ally = entrant(19003, 2)
	local far, farRoot, farHumanoid = entrant(19004, 30)
	GameState.Taggers[enemy], GameState.Taggers[far] = { Since = 0 }, { Since = 0 }
	GameState.RefreshSpeed(enemy)
	local function equip(id)
		store:SetAsync("u_19001", { Beasts = id and { [id] = true } or {}, EquippedBeast = id })
		PlayerDataStore.Load(player)
		GameState.ResetData(player)
	end

	ItemManager.Start()
	equip(nil)
	check("未装備の参加者は召喚できない", not ItemManager.UseBeast(player))
	equip("Bastet")
	GameState.Phase = "Intermission"
	check("ラウンド外では召喚できない", not ItemManager.UseBeast(player))
	GameState.Phase = "Round"
	local data = GameState.GetData(player)
	data.StunUntil = now + 1
	check("スタン中は召喚を消費しない", not ItemManager.UseBeast(player) and not data.BeastUsed)
	GameState.ClearStun(player)
	GameState.TryDown(player)
	check("転倒中は召喚を消費しない", not ItemManager.UseBeast(player) and not data.BeastUsed)
	GameState.ClearDown(player)

	ZoneManager.Start(120)
	root.Position = ZoneManager.GetCenter() + Vector3.new(ZoneManager.GetRadius() + 10, 4, 0)
	check("バステトで速度上昇・同じ試合では再召喚不可",
		ItemManager.UseBeast(player) and humanoid.WalkSpeed > Config.NormalWalkSpeed and not ItemManager.UseBeast(player))
	local model = RT.workspace:FindFirstChild("Bastet")
	check("召喚したモデルが Workspace に出る", model ~= nil)
	now += Config.BeastModelDuration
	ItemManager.Tick()
	ZoneManager.Tick()
	check("数秒でモデルが消え、ゾーン外のスタミナが減らない",
		model and model.Parent == nil and data.ZoneStamina == Config.ZoneStaminaMax)
	now = 100 + Config.Beasts.Bastet.Duration
	ItemManager.Tick()
	ZoneManager.Tick()
	check("バステト終了後は速度が戻り、スタミナが減る",
		near(humanoid.WalkSpeed, Config.NormalWalkSpeed) and data.ZoneStamina < Config.ZoneStaminaMax
		and not ItemManager.UseBeast(player))
	ZoneManager.Stop()

	root.Position = Vector3.new(0, 4, 0)
	equip("Sobek")
	check("次の試合は召喚でき、セベクは範囲内の相手を転倒させる",
		ItemManager.UseBeast(player) and GameState.IsDowned(enemy) and enemyHumanoid.WalkSpeed == 0
			and not GameState.IsDowned(ally) and not GameState.IsDowned(far))
	now += Config.Beasts.Sobek.Duration
	ItemManager.Tick()
	check("セベクの転倒は1.5秒で解除される",
		GameState.GetData(enemy).DownUntil == 0 and enemyHumanoid.WalkSpeed == Config.TaggerWalkSpeed)

	equip("Sekhmet")
	check("セクメトで付近の相手だけが減速する", ItemManager.UseBeast(player)
		and near(enemyHumanoid.WalkSpeed, Config.TaggerWalkSpeed * Config.Beasts.Sekhmet.SpeedMultiplier)
		and GameState.GetData(far).BeastSlowUntil == 0 and GameState.GetData(ally).BeastSlowUntil == 0)
	now += Config.Beasts.Sekhmet.Duration
	ItemManager.Tick()
	check("セクメトの減速は4秒で切れる", near(enemyHumanoid.WalkSpeed, Config.TaggerWalkSpeed))

	equip("Horus")
	check("ホルスで速度とジャンプが上がる", ItemManager.UseBeast(player)
		and humanoid.WalkSpeed > Config.NormalWalkSpeed and humanoid.JumpHeight > Config.NormalJumpHeight)
	now += Config.Beasts.Horus.Duration
	ItemManager.Tick()
	check("ホルスの速度とジャンプは6秒で戻る",
		near(humanoid.WalkSpeed, Config.NormalWalkSpeed) and near(humanoid.JumpHeight, Config.NormalJumpHeight))

	equip("Thoth")
	local radarCalls = {}
	Remotes.RadarEffect.FireClient = function(_, recipient, targets, duration)
		table.insert(radarCalls, { recipient, targets, duration })
	end
	check("トトは参加者全員の姿を召喚者だけに5秒間表示する", ItemManager.UseBeast(player) and #radarCalls == 1
		and radarCalls[1][1] == player and #radarCalls[1][2] == 4 and radarCalls[1][3] == 5)
	Remotes.RadarEffect.FireClient = nil

	equip("Anubis")
	RT.workspace._blockcast = function()
		return { Distance = 8 }
	end
	check("アヌビスは壁の手前にワープし、3秒間タッチを無効にする",
		ItemManager.UseBeast(player) and near(root.Position.Z, -7) and GameState.GetData(player).InvulnerableUntil == now + 3)
	RT.workspace._blockcast = nil
	now += Config.Beasts.Anubis.Duration
	check("アヌビスのタッチ無効は3秒で切れる", GameState.GetData(player).InvulnerableUntil <= GameState.Now())

	equip("Khepri")
	check("ケプリは前方に加速し、通常より長くダッシュする", ItemManager.UseBeast(player)
		and GameState.GetData(player).DashUntil > now + Config.Items.Dash.Duration
		and root.AssemblyLinearVelocity.Z < 0)
	local khepriData = GameState.GetData(player)
	local khepriDeadline = khepriData.DashUntil
	ItemManager.GrantItem(player, "Dash")
	ItemManager.TryUse(player, 1)
	check("ケプリ使用直後にダッシュを使っても加速期限は短くならない",
		#khepriData.HeldItems == 0 and khepriData.DashUntil == khepriDeadline)

	equip("Hathor")
	GameState.TryDown(player)
	GameState.ApplyStun(player, 2)
	GameState.GetData(player).ZoneStamina = 10
	check("ハトホルは転倒とスタンを解除しスタミナを全回復する",
		ItemManager.UseBeast(player) and not GameState.IsDowned(player) and not GameState.IsStunned(player)
			and humanoid.WalkSpeed == Config.NormalWalkSpeed
			and GameState.GetData(player).ZoneStamina == Config.ZoneStaminaMax)

	equip("Ra")
	farRoot.Position = Vector3.new(15, 4, -7)
	check("ラーは15スタッド以内の相手全員を2秒間スタンさせる", ItemManager.UseBeast(player)
		and GameState.GetData(enemy).StunUntil == now + 2
		and GameState.GetData(far).StunUntil == now + 2 and not GameState.IsStunned(ally))
	now += 2
	ItemManager.Tick()
	check("ラーのスタンが切れると動ける", enemyHumanoid.WalkSpeed == Config.TaggerWalkSpeed)

	local map = RT.workspace:FindFirstChild(MapBuilder.MapFolderName)
	local createdMap = not map
	if createdMap then
		map = RT.Instance.new("Folder")
		map.Name = MapBuilder.MapFolderName
		map.Parent = RT.workspace
	end
	local previousRaycast = RT.workspace._raycast
	RT.workspace._raycast = function(origin)
		return { Instance = map, Position = origin - Vector3.new(0, 4, 0) }
	end
	root.Position = Vector3.new(0, 4, 0)
	enemyRoot.Position = Vector3.new(4, 4, 0)
	farRoot.Position = Vector3.new(30, 12, 0)
	humanoid.FloorMaterial = RT.Enum.Material.Grass
	enemyHumanoid.FloorMaterial = RT.Enum.Material.Grass
	farHumanoid.FloorMaterial = RT.Enum.Material.Air
	equip("Set")
	check("セトは接地中の相手とだけ位置を交換する", ItemManager.UseBeast(player)
		and root.Position.X == 4 and enemyRoot.Position.X == 0
		and farRoot.Position.X == 30 and farRoot.Position.Y == 12)
	equip("Set")
	enemyHumanoid.FloorMaterial = RT.Enum.Material.Air
	check("セトは接地中の相手がいなければ誰も移動させない", ItemManager.UseBeast(player)
		and root.Position.X == 4 and enemyRoot.Position.X == 0 and farRoot.Position.X == 30)
	equip("Set")
	enemyHumanoid.FloorMaterial = RT.Enum.Material.Grass
	RT.workspace._raycast = function(origin)
		return origin.X ~= enemyRoot.Position.X and { Instance = map } or nil
	end
	check("セトは足場のない位置を除外する", ItemManager.UseBeast(player)
		and root.Position.X == 4 and enemyRoot.Position.X == 0)
	equip("Set")
	ZoneManager.Start(120)
	local center = ZoneManager.GetCenter()
	local inside = Vector3.new(center.X, 4, center.Z)
	local outside = inside + Vector3.new(ZoneManager.GetRadius() + 10, 0, 0)
	root.Position = inside
	enemyRoot.Position = outside
	RT.workspace._raycast = function()
		return { Instance = map }
	end
	check("セトはゾーン外の相手と位置を交換しない", ItemManager.UseBeast(player)
		and root.Position == inside and enemyRoot.Position == outside)
	ZoneManager.Stop()
	RT.workspace._raycast = previousRaycast

	equip("Isis")
	local originalGravity = RT.workspace.Gravity
	RT.workspace.Gravity = 196.2
	humanoid.FloorMaterial = RT.Enum.Material.Air
	check("イシスを召喚できる", ItemManager.UseBeast(player))
	ItemManager.TryIsisJump(player)
	check("イシスの空中ジャンプが発動する", root.AssemblyLinearVelocity.Y > 0)
	root.AssemblyLinearVelocity = Vector3.new(0, -1, 0)
	ItemManager.TryIsisJump(player)
	check("イシスの空中ジャンプは着地まで1回", root.AssemblyLinearVelocity.Y == -1)
	humanoid.FloorMaterial = RT.Enum.Material.Grass
	ItemManager.Tick()
	humanoid.FloorMaterial = RT.Enum.Material.Air
	ItemManager.TryIsisJump(player)
	check("イシスの空中ジャンプは着地後に再使用できる", root.AssemblyLinearVelocity.Y > 0)
	RT.workspace.Gravity = originalGravity

	local platforms = map:FindFirstChild("SkyPlatforms")
	local createdPlatforms = not platforms
	if createdPlatforms then
		platforms = RT.Instance.new("Folder")
		platforms.Name = "SkyPlatforms"
		platforms.Parent = map
	end
	local platform = RT.Instance.new("Part")
	platform.Position = Vector3.new(10, 48, 2)
	platform.Size = Vector3.new(12, 4, 12)
	platform.Parent = platforms
	local priorMap = MapBuilder.CurrentMap
	MapBuilder.CurrentMap = "Sky"
	enemyRoot.Position = Vector3.new(0, 54, 0)
	farRoot.Position = Vector3.new(30, 54, 0)
	local allyRoot = GameState.GetRootPart(ally)
	allyRoot.Position = Vector3.new(2, 54, 0)
	GameState.GetData(player).HeldItems = { "SafetyLine" }
	root.Position = Vector3.new(11, Config.FallEliminateY - 1, 2)
	RoundManager.CheckSkyFalls()
	check("イシスの効果中は脱落せず近くの足場に戻り、命綱を消費しない",
		GameState.IsParticipant(player) and root.Position.X == 10 and root.Position.Y > platform.Position.Y
			and #GameState.GetData(player).HeldItems == 1)
	now += Config.Beasts.Isis.Duration
	root.AssemblyLinearVelocity = Vector3.new(0, -1, 0)
	ItemManager.TryIsisJump(player)
	check("イシスの効果は6秒で切れる", root.AssemblyLinearVelocity.Y == -1 and not ItemManager.TrySafetyLine(player))
	MapBuilder.CurrentMap = priorMap
	platform:Destroy()
	if createdPlatforms then
		platforms:Destroy()
	end
	if createdMap then
		map:Destroy()
	end

	equip("Osiris")
	root.Position = Vector3.new(0, 4, -3)
	root.CFrame = RT.CFrame.new(root.Position)
	enemyRoot.Position = Vector3.new(0, 4, 0)
	enemyRoot.CFrame = RT.CFrame.new(enemyRoot.Position)
	check("オシリスでタッチ無効が付く", ItemManager.UseBeast(player)
		and GameState.GetData(player).InvulnerableUntil == now + 10)
	for _ = 1, 2 do
		RoundManager.TryTag()
	end
	check("オシリスの効果中はタッチされても役割が変わらない",
		not GameState.IsTagger(player) and GameState.IsTagger(enemy))
	now += 10
	RoundManager.TryTag()
	check("オシリスの効果が切れるとタッチで役割が変わる", GameState.IsTagger(player))

	ItemManager.Stop()
	for _, entrantPlayer in ipairs({ player, enemy, ally, far }) do
		entrantPlayer.Character:Destroy()
		GameState.Participants[entrantPlayer] = nil
		GameState.Taggers[entrantPlayer] = nil
		GameState.ClearData(entrantPlayer)
		PlayerDataStore.Forget(entrantPlayer)
		entrantPlayer:Destroy()
	end
	GameState.Phase = "Waiting"
	GameState.Now = realNow
end

-- 盤面の各マスの中心は、どの初期角度からでも真上の針で止まる。
do
	local visual = require("./.build/RouletteVisual")
	local count = #Config.Roulette.Prizes
	for index = 1, count do
		local sectorCenter = (index - 1) * 60
		local expectedStop = (360 - sectorCenter) % 360
		local matches = visual.StopAngle(index, count) == expectedStop
		for _, startAngle in ipairs({ 0, 28.5, 359.75, 725, -120 }) do
			local target = visual.TargetRotation(startAngle, index, count)
			local final = visual.SpinAngle(startAngle, target, 1)
			local distance = target - startAngle
			matches = matches and distance >= 4 * 360 and distance < 5 * 360
				and (final + sectorCenter) % 360 == 0
		end
		check(string.format("ルーレット：マス%dの中心が真上の針で止まる", index), matches)
	end
end

-- Studio のメモリ動作に切り替えるので、DataStore を使うテストの最後に実行する。
do
	local store = RT.game:GetService("DataStoreService"):GetDataStore("PlayerData_v1")
	local getService = RT.game.GetService
	local getAsync = store.GetAsync
	RT.game.GetService = function(self, name)
		if name == "RunService" then
			return { IsStudio = function() return true end }
		end
		return getService(self, name)
	end
	store.GetAsync = function()
		error("StudioAccessToApisNotAllowed: Studio access to APIs is not allowed")
	end

	local player = { UserId = 19007 }
	PlayerDataStore.Load(player)
	PlayerDataStore.AddCoins(player, Config.BeastDrawCost, false)
	local result = PlayerDataStore.DrawBeast(player)
	local equipped = result and PlayerDataStore.SetEquippedBeast(player, result.Id)
	local spun, data = PlayerDataStore.SpinRoulette(player, 1, 1000000)
	store.GetAsync = getAsync
	RT.game.GetService = getService

	check("Studio：API 無効時もメモリ上でガチャ・装備・ルーレットを使える",
		result and equipped and spun and data.EquippedBeast == result.Id
			and data.Coins == Config.Roulette.Prizes[1].Coins and store:GetAsync("u_19007") == nil)
	PlayerDataStore.Forget(player)
end

print(string.format("== 結果: 成功 %d / 失敗 %d ==", passed, failed))
if failed > 0 then
	error("テストが失敗しました")
end
