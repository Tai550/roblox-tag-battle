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
RT.modules.ItemManager = require("./.build/ItemManager")
RT.modules.RoundManager = require("./.build/RoundManager")
RT.modules.MapBuilder = require("./.build/MapBuilder")

local Config = RT.modules.Config
local RankManager = RT.modules.RankManager
local Remotes = RT.modules.Remotes
local ZoneManager = RT.modules.ZoneManager
local DeckManager = RT.modules.DeckManager
local ItemManager = RT.modules.ItemManager
local RoundManager = RT.modules.RoundManager
local Vector3 = RT.Vector3

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

print(string.format("== 結果: 成功 %d / 失敗 %d ==", passed, failed))
if failed > 0 then
	os.exit(1)
end
