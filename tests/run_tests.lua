-- run_tests: v2 で追加した計算ロジックと、マップ生成（MapBuilder）のモックテスト
-- 実行前に `python3 tests/build_tests.py` で tests/.build/ を作っておくこと。
-- 実行: luau tests/run_tests.lua

local RT = require("./.build/mockenv")

-- 依存順に本物のモジュールを読み込み、モックの参照表へ登録する
RT.modules.Config = require("./.build/Config")
RT.modules.GameState = require("./.build/GameState")
RT.modules.Remotes = require("./.build/Remotes")
RT.modules.Leaderstats = require("./.build/Leaderstats")
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

math.randomseed(12345)

---------------------------------------------------------------------
-- 1. 縮小エリア：中心と開始半径
---------------------------------------------------------------------

do
	-- 2点 (0,0,0) と (30,0,40): 中心 (15,0,20)、最大距離 25 → 25+15=40 → 下限 50 に丸める
	local cx, cy, cz, radius = ZoneManager.ComputeGeometry({ point(0, 0, 0), point(30, 0, 40) }, false)
	check("中心は出現ポイントの平均", near(cx, 15) and near(cy, 0) and near(cz, 20))
	check("開始半径は下限50に丸める", near(radius, 50))

	-- 2点 (0,0,0) と (200,0,0): 中心 (100,0,0)、最大距離 100 → 115（上限内）
	local _, _, _, radius2 = ZoneManager.ComputeGeometry({ point(0, 0, 0), point(200, 0, 0) }, false)
	check("開始半径は最大距離+15", near(radius2, 115))

	-- 2点 (0,0,0) と (300,0,0): 最大距離 150 → 165 → 上限 120 に丸める
	local _, _, _, radius3 = ZoneManager.ComputeGeometry({ point(0, 0, 0), point(300, 0, 0) }, false)
	check("開始半径は上限120に丸める", near(radius3, 120))

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
	-- 180秒・開始半径120: 縮小は144秒まで。72秒で半分 → 120 + (18-120)*0.5 = 69
	check("縮小開始直後は開始半径", near(ZoneManager.RadiusAt(0, 180, 120), 120))
	check("縮小区間の中間で線形に縮む", near(ZoneManager.RadiusAt(72, 180, 120), 69))
	check("80%時点で終了半径18", near(ZoneManager.RadiusAt(144, 180, 120), 18))
	check("80%を過ぎたら終了半径で固定", near(ZoneManager.RadiusAt(180, 180, 120), 18))
	-- 60秒・開始半径60: 縮小は48秒まで
	check("60秒試合でも80%で終了半径", near(ZoneManager.RadiusAt(48, 60, 60), 18))
	check("60秒試合の途中経過", near(ZoneManager.RadiusAt(24, 60, 60), 39))
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
	local okValid = DeckManager.ValidateDeck({ "Dash", "Shield", "Warp" })
	check("正しいデッキは通る", okValid == true)
	local okDup = DeckManager.ValidateDeck({ "Dash", "Dash", "Warp" })
	check("重複は通らない", okDup == false)
	local okCount = DeckManager.ValidateDeck({ "Dash", "Shield" })
	check("数が違うと通らない", okCount == false)
	local okUnknown = DeckManager.ValidateDeck({ "Dash", "Shield", "NoSuchItem" })
	check("存在しないアイテムは通らない", okUnknown == false)
	local okType = DeckManager.ValidateDeck("Dash")
	check("配列でないと通らない", okType == false)

	-- 既定デッキから300回引いて、デッキ外が絶対に出ないこと
	local fakePlayer = { Parent = {} }
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
	check("300回引けばデッキの3種すべて出る", seenCount == 3)

	-- デッキを変更したら、その中からだけ出る
	local okSet = DeckManager.SetDeck(fakePlayer, { "Smoke", "Star", "Banana" })
	check("デッキ変更が受理される", okSet == true)
	local changedSet = { Smoke = true, Star = true, Banana = true }
	local allInChanged = true
	for _ = 1, 300 do
		local picked = DeckManager.PickFromDeck(fakePlayer)
		if not changedSet[picked] then
			allInChanged = false
		end
	end
	check("変更後の抽選もデッキの中からだけ出る", allInChanged)

	-- 不正なデッキ変更は今のデッキを壊さない
	local okBad = DeckManager.SetDeck(fakePlayer, { "Dash", "Dash", "Dash" })
	check("不正なデッキ変更は却下される", okBad == false)
	local stillIn = true
	for _ = 1, 100 do
		local picked = DeckManager.PickFromDeck(fakePlayer)
		if not changedSet[picked] then
			stillIn = false
		end
	end
	check("却下されても前のデッキのまま", stillIn)
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
		if math.abs(p.Position.X) > 115 or math.abs(p.Position.Z) > 115 then
			allInside = false
		end
		if not (p.Transparency == 1 and p.CanCollide == false and p.Anchored == true
			and p.Size.X == 2 and p.Size.Y == 1 and p.Size.Z == 2) then
			allMarker = false
		end
	end
	check("出現ポイントはすべて舞台の範囲内（|x|,|z| <= 115）", allInside)
	check("出現ポイントは 2×1×2・透明・当たり判定なし・固定", allMarker)

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
	for _, p in ipairs(MapBuilder.ItemSpawnPositions()) do
		for _, b in ipairs(MapBuilder.Buildings) do
			local inX = math.abs(p.x - b.x) < b.w / 2 + 1
			local inZ = math.abs(p.z - b.z) < b.d / 2 + 1
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
	check("読み直した leaderstats も同じ", stat(loaded, "RP") == 250 and stat(loaded, "Survived") == 2
		and stat(loaded, "Tagged") == 1 and stat(loaded, "Rank") == "ゴールド")
	check("保存済みの段位を読み込んでも RankUp は飛ばない", fired.n == 0)
	RankManager.Load(loaded)
	check("同じ参加の再読み込みでは RP は増えない", RankManager.Get(loaded).RP == 250)

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

	GameState.Tagger = playerA
	TaggerLook.Follow(playerA)
	local highlightA = charA:FindFirstChild(TaggerLook.HighlightName)
	check("鬼の各 Part が元の色と赤の中間になる", sameColor(headA, mixedWhite) and sameColor(torsoA, mixedBlue))
	check("鬼には Highlight が付き、塗りは薄め", highlightA ~= nil
		and highlightA.FillTransparency >= 0.6 and highlightA.FillTransparency < 1
		and highlightA.OutlineTransparency < 1)
	check("鬼でない人には色も Highlight も付かない", sameColor(headB, white)
		and charB:FindFirstChild(TaggerLook.HighlightName) == nil)

	TaggerLook.Follow(playerA)
	check("同じ鬼に二度付けても色は二重に混ざらない", sameColor(headA, mixedWhite)
		and not sameColor(headA, TaggerLook.MixColor(mixedWhite)))

	GameState.Tagger = playerB
	TaggerLook.Follow(playerB)
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

	GameState.Tagger = nil
	TaggerLook.Follow(nil)
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

	local first = MapBuilder.BuildNextRound()
	local firstSpawns = baseParts(spawnFolder())
	local firstInside = true
	for _, part in ipairs(firstSpawns) do
		if math.abs(part.Position.X) > 115 or math.abs(part.Position.Z) > 115 then
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
		if math.abs(part.Position.X) > 115 or math.abs(part.Position.Z) > 115 then
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
		if part.Name == "Grass" and part.Size.X >= 340 and part.Size.Z >= 340 then
			grassOk = true
		end
		local color = part.Color
		if color and color.R == 255 and color.G == 255 and color.B == 255 then
			white = white + 1
		end
	end
	check("入れ替え2回目はパーク（14点）", second.MapId == "Park" and MapBuilder.CurrentMap == "Park"
		and second.ItemSpawns == 14 and #parkSpawns == 14 and #MapBuilder.ParkSpawnPositions() == 14)
	check("パークの出現ポイントは 340×340 の内側で、渋谷より外側まで散らばる", inPark and spreadsBeyond and hasPos and hasNeg)
	check("パークの Part 数は 500 以下", second.PartCount <= 500 and second.PartCount == #parkParts + #parkSpawns)
	print(string.format("    （パークの BasePart %d ＋ 出現ポイント %d ＝ %d）", #parkParts, #parkSpawns, second.PartCount))
	check("パークは中央広場にスポーンが1つ、外周の透明な壁が4枚、芝生の地面", spawnLocations == 1
		and spawnAtCenter and wallCount == 4 and grassOk)
	check("パークは渋谷の横断歩道（白い帯）を持たない", white < 36 and second.ClimbableBuildings == 0)

	local parkPoints, parkFallback = ItemManager.GetSpawnPoints()
	local _, _, _, parkRadius = ZoneManager.ComputeGeometry(parkPoints, false)
	check("パークの出現ポイントでもゾーンの開始半径が計算できる", #parkPoints == 14 and parkFallback == false
		and parkRadius >= Config.ZoneStartRadiusMin and parkRadius <= Config.ZoneStartRadiusMax)
	check("広いパークの開始半径は上限 120 に丸まる", near(parkRadius, Config.ZoneStartRadiusMax))

	-- 明示的な Build() は表示中のマップだけを作り直す。
	local rebuilt = MapBuilder.Build()
	check("途中の Build() は渋谷を作り直すだけ", rebuilt.MapId == "Shibuya" and MapBuilder.CurrentMap == "Shibuya")
	local lighting = RT.game:GetService("Lighting")
	local originalBrightness = lighting.Brightness
	local dungeonLimits = { Cave = 400, Ice = 300, Volt = 350, Sky = 300 }
	for _, expected in ipairs({
		{ "Cave", "None", "Phase" },
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
		if id == "Cave" then
			check("洞窟では暗くなる", lighting.Brightness < originalBrightness)
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
		GameState.Tagger = nil

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
		local fromDeck = data.HeldItems[1] == "Dash" or data.HeldItems[1] == "Shield" or data.HeldItems[1] == "Warp"
		check("蓋に触れてもデッキのアイテムが1つ手に入る", #data.HeldItems == 1 and fromDeck
			and data.HeldExpireAt[1] > 0)
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
	Remotes.DeckUpdate.FireClient = spy("DeckUpdate")
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
		DeckManager.SetDeck(bot, { "Dash", "Shield", "Warp" })
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
	GameState.Tagger = nil
	local humans = { {}, {}, {} }
	BotManager.Fill(humans)
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
	GameState.Tagger = spawned[1]
	TaggerLook.Follow(spawned[1])
	local tinted = head and head.Color and headBefore
		and not (near(head.Color.G, headBefore.G) and near(head.Color.B, headBefore.B))
	local highlight = body and body:FindFirstChild(TaggerLook.HighlightName)
	check("ボットが鬼になると TaggerLook で赤みと Highlight が付く", tinted and highlight ~= nil)
	TaggerLook.Follow(nil)
	GameState.Tagger = nil
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
	local fromDeck = held[1] == "Dash" or held[1] == "Shield" or held[1] == "Warp"
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
	GameState.Tagger = nil
	GameState.Participants = {}
	ZoneManager.Stop()
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
	GameState.Tagger = bot
	hazard.Touched:_Fire(root)
	hazard.Touched:_Fire(botRoot)
	check("帯電部品との接触で人間と鬼ボットが痺れる",
		near(data.StunUntil, now + 1.2) and GameState.IsStunned(bot)
		and humanoid.WalkSpeed == 0 and humanoid.JumpPower == 0 and humanoid.JumpHeight == 0
		and botHumanoid.WalkSpeed == 0)
	now += 1.2
	ItemManager.Tick()
	check("痺れの終了で速度とジャンプが戻る", data.StunUntil == 0 and humanoid.WalkSpeed == Config.NormalWalkSpeed
		and humanoid.JumpPower == 50 and humanoid.JumpHeight == 7)
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
	GameState.Tagger = bot
	botRoot.Position = Vector3.new(0, Config.FallEliminateY - 1, 0)
	RoundManager.CheckSkyFalls()
	check("鬼ボットは命綱を使わず、落下脱落すると残った人へ鬼が交代する",
		not GameState.IsParticipant(bot) and GameState.Eliminated[bot] == "落下で脱落"
		and #botData.HeldItems == 1 and GameState.Tagger == player)
	root.Position = Vector3.new(0, Config.FallEliminateY - 1, 0)
	RoundManager.CheckSkyFalls()
	check("命綱は一度限りで、次の落下では脱落して観戦位置へ移る",
		not GameState.IsParticipant(player) and GameState.Eliminated[player] == "落下で脱落"
		and root.Anchored and root.Position.Y > sky:FindFirstChild("PlayerSpawn").Position.Y
		and GameState.Tagger == nil)

	TaggerLook.Follow(nil)
	ItemManager.Stop()
	for _, entity in ipairs({ player, bot }) do
		GameState.UnregisterCharacter(entity.Character)
		GameState.ClearData(entity)
		entity.Character:Destroy()
	end
	GameState.Eliminated = {}
	GameState.BeenTagger = {}
	GameState.Now = realNow
	GameState.Phase = "Waiting"
end

print(string.format("== 結果: 成功 %d / 失敗 %d ==", passed, failed))
if failed > 0 then
	error("テストが失敗しました")
end
