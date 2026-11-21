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
RT.modules.VoltGimmicks = require("./.build/VoltGimmicks")
RT.modules.ItemManager = require("./.build/ItemManager")
RT.modules.TaggerSkills = require("./.build/TaggerSkills")
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
-- ロビーメニュー：権限別の表示と項目の並び
---------------------------------------------------------------------

do
	local LobbyMenu = require("./.build/LobbyMenu")
	local function itemIds(items)
		local ids = {}
		for _, item in ipairs(items) do
			table.insert(ids, item.Id)
		end
		return ids
	end

	local expected = "Status,Deck,Shop,Store,Room,Roulette,Beasts,Trade,Solo"
	check("ロビーメニュー：一般プレイヤーは9項目を定義順に表示",
		table.concat(itemIds(LobbyMenu.VisibleItems(false)), ",") == expected)

	local adminIds = itemIds(LobbyMenu.VisibleItems(true))
	check("ロビーメニュー：管理者は管理を含む10項目を定義順に表示",
		table.concat(adminIds, ",") == expected .. ",Admin")

	local items = LobbyMenu.VisibleItems(false)
	check("ロビーメニュー：先頭にステータスを表示",
		items[1].Id == "Status" and items[1].Label == "ステータス")
	check("ロビーメニュー：アイテム購入とショップのラベル",
		items[3].Id == "Shop" and items[3].Label == "アイテム購入"
		and items[4].Id == "Store" and items[4].Label == "ショップ")

	local seen = {}
	local unique = true
	for _, id in ipairs(adminIds) do
		if seen[id] then
			unique = false
		end
		seen[id] = true
	end
	check("ロビーメニュー：項目IDに重複がない", unique)
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
	check("基本アイテムは全部で28種", count == 28 and #Config.ItemOrder == 28)
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
-- デッキの組み合わせ
---------------------------------------------------------------------

do
	local highJump = Config.FindCombos({ "Grapple", "HighJump" })
	check("コンボ：2つのアイテムが順不同でそろうと発動する",
		#highJump == 1 and highJump[1].Id == "HighJumpGrapple")
	check("コンボ：片方だけや同じアイテムの重複では発動しない",
		#Config.FindCombos({ "HighJump", "HighJump" }) == 0)
	local double = Config.FindCombos({ "Reflect", "Grapple", "Shield", "HighJump" })
	check("コンボ：4枠で2組が同時に発動する",
		#double == 2 and double[1].Id == "HighJumpGrapple" and double[2].Id == "ShieldReflect")
	check("コンボ：ダンジョン固有アイテムだけでは発動しない",
		#Config.FindCombos({ "Phase", "SpikeBoots", "Insulate", "SafetyLine" }) == 0)
	check("コンボ：表示にはアイテム名と効果説明を使う",
		Config.ItemComboText(highJump[1]) == Config.Items.HighJump.DisplayName .. " ＋ "
			.. Config.Items.Grapple.DisplayName .. "\n移動速度 +3%")
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

do
	local player = RT.Instance.new("Player")
	local character = RT.Instance.new("Model")
	player.Character = character
	local root = RT.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = Vector3.new(500, 3, 0)
	root.Parent = character
	local humanoid = RT.Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.Parent = character
	GameState.Participants[player] = true

	local realNow = GameState.Now
	local now = 0
	GameState.Now = function() return now end
	ZoneManager.Start(180)
	local data = GameState.GetData(player)

	now = 1
	ZoneManager.Tick()
	check("エリア外では1秒でスタミナが18減る", near(data.ZoneStamina, 82))

	now = 5.5
	ZoneManager.Tick()
	check("エリア外では5.5秒でスタミナが1残る",
		near(data.ZoneStamina, 1) and data.ZoneReturns == 0)

	now = 5.75
	ZoneManager.Tick()
	check("次の判定でスタミナが尽きて強制送還される",
		data.ZoneReturns == 1 and data.ZoneStamina == Config.ZoneStaminaMax)

	root.Position = ZoneManager.GetCenter()
	data.ZoneStamina = 10
	data.ActiveCombos.ShieldReflect = true
	now += 1
	ZoneManager.Tick()
	check("コンボ：エリアに戻ったときのスタミナ回復が1.5倍",
		near(data.ZoneStamina, 10 + Config.ZoneRegenPerSecond * 1.5))
	now += 10
	ZoneManager.Tick()
	check("コンボ：回復はスタミナの上限を超えない", data.ZoneStamina == Config.ZoneStaminaMax)

	ZoneManager.Stop()
	GameState.Now = realNow
	GameState.Participants[player] = nil
	GameState.ClearData(player)
	character:Destroy()
	player:Destroy()
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

	local tallyStrength = RoundManager.TallyBotStrengthVotes
	local choice, strengthCounts = tallyStrength({})
	check("ボットの強さ投票：無投票はおまかせで全選択肢が0票",
		choice == "Auto" and strengthCounts.Weak == 0 and strengthCounts.Normal == 0
		and strengthCounts.Strong == 0 and strengthCounts.Auto == 0)
	choice, strengthCounts = tallyStrength({ "Weak", "Normal", "Strong", "Strong", "Auto" })
	check("ボットの強さ投票：単独最多のつよいを採用",
		choice == "Strong" and strengthCounts.Strong == 2 and strengthCounts.Auto == 1)
	check("ボットの強さ投票：最多が同数ならおまかせ",
		tallyStrength({ "Weak", "Weak", "Normal", "Normal", "Strong" }) == "Auto")
	choice, strengthCounts = tallyStrength({ "Unknown", {}, false, 3, "Weak" })
	check("ボットの強さ投票：有効な票だけを数える",
		choice == "Weak" and strengthCounts.Weak == 1 and strengthCounts.Unknown == nil)
	check("ボットの強さ投票：無効票だけならおまかせ",
		tallyStrength({ "Unknown", {}, false, 3 }) == "Auto")
	check("ボットの強さ投票：おまかせも投票できる",
		tallyStrength({ "Auto", "Auto", "Weak" }) == "Auto")

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
	check("鬼は離れた相手を追うときダッシュを使う", BotManager.ShouldUseItem("Dash", true, 30)
		and not BotManager.ShouldUseItem("Dash", true, math.huge))
	local shrunkX, _, shrunkReason = BotManager.ChooseGoal({
		Role = "Runner", X = 40, ZoneActive = true, ZoneShrunk = true, ZoneRadius = 50,
	})
	check("縮小中は手前で内側に向かい、さらに中心に寄る", shrunkReason == "zone" and shrunkX < zoneX)
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
	BotManager.SetRoundStrengthChoice("Weak")
	local weak, fixedAverage = BotManager.Fill({ masterA, masterB })
	local weakSpeed, weakInterval = BotManager.StrengthForTierIndex(1)
	local weakOk = #weak == 6 and fixedAverage == nil
	for _, bot in ipairs(weak) do
		weakOk = weakOk and bot.SpeedMultiplier == weakSpeed and bot.RepathInterval == weakInterval
	end
	check("ボットの強さ：補充では参加者の平均段位より投票結果を優先", weakOk)

	BotManager.SetRoundStrengthChoice("Auto")
	local strong, averageTier = BotManager.Fill({ masterA, masterB })
	local strongOk = #strong == 6
	local _, strongInterval = BotManager.StrengthForTierIndex(#Config.RankTiers)
	for _, spawnedBot in ipairs(strong) do
		if spawnedBot.SpeedMultiplier ~= Config.BotSpeedMultiplierCap or spawnedBot.RepathInterval ~= strongInterval then
			strongOk = false
		end
		local botHumanoid = spawnedBot.Character and spawnedBot.Character:FindFirstChildOfClass("Humanoid")
		if not botHumanoid or not near(botHumanoid.WalkSpeed, Config.NormalWalkSpeed * Config.BotSpeedMultiplierCap) then
			strongOk = false
		end
	end
	check("おまかせ：平均がマスターなら速さと経路間隔に最上位の設定を使う",
		strongOk and averageTier == #Config.RankTiers)

	for _, expected in ipairs({
		{ Id = "Weak", TierIndex = 1 },
		{ Id = "Normal", TierIndex = 3 },
		{ Id = "Strong", TierIndex = #Config.RankTiers },
	}) do
		BotManager.SetRoundStrengthChoice(expected.Id)
		local bot = BotManager.Spawn(1, { SoloCap = true })[1]
		local speed, interval = BotManager.StrengthForTierIndex(expected.TierIndex)
		check("ボットの強さ：ソロの段位対応と速度上限 " .. expected.Id,
			bot.SpeedMultiplier == speed and bot.RepathInterval == interval and bot.SoloCap
			and near(GameState.GetHumanoid(bot).WalkSpeed, math.min(Config.NormalWalkSpeed * speed, Config.BotRunnerWalkSpeed)))
	end
	BotManager.Clear()
	local defaultBot = BotManager.Spawn(1)[1]
	check("ボットの強さ：ラウンド終了後のソロは既定の強さに戻る",
		defaultBot.SpeedMultiplier == 1 and defaultBot.RepathInterval == nil)
	BotManager.Clear()

	GameState.Phase = "Waiting"
	GameState.Taggers = {}
	GameState.Participants = {}
	ZoneManager.Stop()
end

---------------------------------------------------------------------
-- ボットの高所追跡と立て直し
do
	local now = 100
	local realNow = GameState.Now
	local oldPhase, oldMap = GameState.Phase, MapBuilder.CurrentMap
	local service = RT.game:GetService("PathfindingService")
	local oldCreatePath, oldRaycast = service.CreatePath, RT.workspace._raycast
	local targets = {}
	local oldSpawn = RT.task.spawn
	RT.task.spawn = function(callback)
		assert(coroutine.resume(coroutine.create(callback)))
	end
	local pathWorks = true
	service.CreatePath = function()
		return {
			Status = pathWorks and RT.Enum.PathStatus.Success or RT.Enum.PathStatus.NoPath,
			ComputeAsync = function(_, _, target)
				table.insert(targets, target)
			end,
			GetWaypoints = function()
				return {
					{ Position = Vector3.new(-6, 0, 0), Action = RT.Enum.PathWaypointAction.Jump },
					{ Position = Vector3.new(0, 6, 0) },
				}
			end,
		}
	end
	RT.workspace._raycast = function(origin, direction)
		if direction.Y < 0 and direction.X == 0 and direction.Z == 0 then
			local y = math.abs(origin.X) <= 4 and math.abs(origin.Z) <= 4 and 6 or 0
			if origin.Y >= y then
				return { Position = Vector3.new(origin.X, y, origin.Z) }
			end
		end
	end
	GameState.Now = function() return now end
	GameState.Phase, MapBuilder.CurrentMap = "Round", "Arena"

	local bot = BotManager.Spawn(1)[1]
	local root, humanoid = GameState.GetRootPart(bot), GameState.GetHumanoid(bot)
	local runner = { Character = RT.Instance.new("Model") }
	local runnerRoot = RT.Instance.new("Part")
	runnerRoot.Name = "HumanoidRootPart"
	runnerRoot.Parent = runner.Character
	local runnerHumanoid = RT.Instance.new("Humanoid")
	runnerHumanoid.Health = 100
	runnerHumanoid.Parent = runner.Character
	GameState.Participants[runner] = true
	GameState.Taggers[bot] = { Since = 0 }
	root.Position = Vector3.new(-10, humanoid.HipHeight + root.Size.Y / 2, 0)
	local floorRootY = root.Position.Y
	runnerRoot.Position = Vector3.new(0, floorRootY + 6, 0)
	runnerRoot.AssemblyLinearVelocity = Vector3.new(8, 5, 0)

	BotManager.Tick()
	local target = targets[1]
	check("高所の追跡は実際の Y と速度による先読みを経路探索に渡す",
		target and near(target.Y, runnerRoot.Position.Y) and near(target.X, 8 * Config.BotPredictionTime))
	check("ジャンプ点へ近づくまではジャンプしない", humanoid.Jump ~= true)
	root.Position = Vector3.new(-6, floorRootY, 0)
	now += 0.1
	BotManager.Tick()
	check("ジャンプ点の手前で経路のジャンプを実行する", humanoid.Jump == true)

	local capped = BotManager.PredictPosition(Vector3.new(0, 10, 0), Vector3.new(1000, -30, 0))
	check("先読みは水平移動だけを使い上限距離で止まる", near(capped.X, Config.BotPredictionMaxDistance) and capped.Y == 10)

	root.Position = Vector3.new(-10, floorRootY, 0)
	-- 成功した経路でも足踏みが続く場合は別の側から試す。
	now += 0.1
	BotManager.Tick()
	now += Config.BotProgressTimeout + 0.1
	BotManager.Tick()
	local recovery = bot.Recovery
	local first = recovery and recovery.Candidates[1]
	check("距離が縮まらない状態が続くと、身近な台の縁に向けて立て直す",
		first and first.Position.X < 0 and first.Position.Y == 0 and first.Landing.Y == 6)

	pathWorks = false
	if first then
		root.Position = Vector3.new(first.Position.X, floorRootY, first.Position.Z)
	end
	humanoid.Jump = false
	now += 0.1
	BotManager.Tick()
	check("経路なしで縁に着いたら台に向けてジャンプする", recovery and recovery.Jumping and humanoid.Jump == true)
	now += Config.BotApproachJumpTime + 0.1
	BotManager.Tick()
	local second = recovery and recovery.Candidates[2]
	check("ジャンプで登れなければ別方向の候補へ切り替える",
		second and recovery.Index == 2 and first.Index ~= second.Index)
	if second then
		root.Position = Vector3.new(second.Position.X, floorRootY, second.Position.Z)
	end
	now += 0.1
	BotManager.Tick()
	if second then
		root.Position = Vector3.new(second.Landing.X, floorRootY + 6, second.Landing.Z)
	end
	pathWorks = true
	now += 0.1
	BotManager.Tick()
	check("台に登ったら通常追跡に復帰する", bot.Recovery == nil and bot.Waypoints ~= nil)

	root.Position = Vector3.new(-10, floorRootY, 0)
	pathWorks = false
	now += Config.BotSoloRepathInterval + 0.1
	BotManager.Tick()
	check("最初から高所への経路がなければ進捗タイムアウトを待たずに縁を探す", bot.Recovery ~= nil)

	local tried = {}
	for _ = 1, Config.BotApproachDirections + 3 do
		local active = bot.Recovery
		local candidate = active and active.Candidates[active.Index]
		if candidate then
			assert(not tried[candidate.Index], "同じ高所候補を再試行")
			tried[candidate.Index] = true
		end
		now += Config.BotApproachTimeout + Config.BotProgressTimeout + 1
		BotManager.Tick()
	end
	check("高所の失敗候補を使い切ると通常追跡を続ける", next(tried) ~= nil and bot.Recovery == nil)

	runnerRoot.Position += Vector3.new(0, 30, 0)
	RT.workspace._raycast = function(origin, direction)
		if direction.Y < 0 and direction.X == 0 and direction.Z == 0 then
			local y = math.abs(origin.X) <= 4 and math.abs(origin.Z) <= 4 and 36 or 0
			if origin.Y >= y then
				return { Position = Vector3.new(origin.X, y, origin.Z) }
			end
		end
	end
	for _ = 1, 4 do
		now += Config.BotApproachTimeout + Config.BotProgressTimeout + 1
		BotManager.Tick()
	end
	check("跳躍できない高さでは停滞が続いても縁へ向かわない", bot.Recovery == nil
		and bot.ApproachAttempts and bot.ApproachAttempts.Exhausted)

	local suspended
	local computes = 0
	service.CreatePath = function()
		return {
			Status = RT.Enum.PathStatus.Success,
			ComputeAsync = function()
				computes += 1
				suspended = coroutine.running()
				coroutine.yield()
			end,
			GetWaypoints = function()
				return { { Position = Vector3.new(999, 0, 0) } }
			end,
		}
	end
	local destination
	humanoid.MoveTo = function(_, position) destination = position end
	now += Config.BotSoloRepathInterval + 1
	BotManager.Tick()
	runnerRoot.Position = Vector3.new(-40, floorRootY, 0)
	now += Config.BotSoloRepathInterval + 1
	BotManager.Tick()
	check("非同期の経路計算中も更新して直進し二重計算しない",
		suspended and computes == 1 and destination and destination.X == -40)
	if suspended then
		assert(coroutine.resume(suspended))
	end
	now += Config.BotDecisionInterval + 0.01
	BotManager.Tick()
	check("移動した目標への古い経路を採用しない", bot.Waypoints == nil
		and destination and destination.X == -40)

	root.Position = Vector3.new(-28, floorRootY, 0)
	now += Config.BotDecisionInterval + 0.01
	if not bot.PathComputing then
		BotManager.Tick()
	end
	if bot.PathComputing and suspended then
		BotManager.Halt()
		assert(coroutine.resume(suspended))
	end
	check("ラウンド停止前の経路計算結果を破棄する", computes == 2
		and not bot.PathComputing and not bot.PathResult and not bot.Waypoints)
	RT.task.spawn = oldSpawn

	BotManager.DespawnAll()
	GameState.Participants[runner] = nil
	runner.Character:Destroy()
	GameState.Now = realNow
	GameState.Phase, MapBuilder.CurrentMap = oldPhase, oldMap
	service.CreatePath, RT.workspace._raycast = oldCreatePath, oldRaycast
end

---------------------------------------------------------------------
-- 鬼ボットの視界、切り返し、疲れ
do
	local cfg = Config.BotChase
	local start, ramp = cfg.FatigueStartSeconds, cfg.FatigueRampSeconds
	local fatigue = BotManager.ChaseFatigueMultiplier
	check("鬼ボットの疲れは20秒まで速度を落とさない", fatigue(0) == 1 and fatigue(20) == 1)
	check("鬼ボットの疲れは段階的に進み最大5%で止まる",
		near(fatigue(start + ramp / 2), 0.975) and near(fatigue(start + ramp), 0.95)
		and near(fatigue(start + 10 * ramp), 0.95))

	local oldHeading, newHeading = Vector3.new(16, 0, 0), Vector3.new(-16, 0, 0)
	local err = BotManager.ChaseTurnError(oldHeading, newHeading, cfg.TurnWindowSeconds)
	local position = Vector3.new(10, 4, 0)
	local predicted = BotManager.PredictPosition(position, newHeading)
	check("鬼ボットは急な切り返しで前の方向に6スタッド狙いを外す",
		err and near(BotManager.ChaseAim(position, newHeading, err, cfg.ErrorSeconds, 0).X, predicted.X + 6))
	check("鬼ボットの狙いの誤差は0.8秒で消える",
		err and near(BotManager.ChaseAim(position, newHeading, err, cfg.ErrorSeconds, 0.8).X, predicted.X))
	check("同方向、停止、時間をおいた反転は切り返しとして扱わない",
		not BotManager.ChaseTurnError(oldHeading, oldHeading, 0)
		and not BotManager.ChaseTurnError(oldHeading, Vector3.new(0, 20, 0), 0)
		and not BotManager.ChaseTurnError(oldHeading, newHeading, cfg.TurnWindowSeconds + 0.1))
	local _, lostReason = BotManager.LostChaseGoal(position, Vector3.new(0, 4, 0), 0, nil, cfg.LastSeenTimeout)
	check("鬼ボットは最後に見た場所への到達が困難なら打ち切る", lostReason == "patrol")

	local now = 100
	local oldNow, oldRay = GameState.Now, RT.workspace._raycast
	local oldPhase, oldMap = GameState.Phase, MapBuilder.CurrentMap
	local oldTimeLeft = GameState.TimeLeft
	GameState.Now = function() return now end
	GameState.Phase, MapBuilder.CurrentMap = "Round", "Arena"
	GameState.TimeLeft = math.huge
	local bot, runner, other = table.unpack(BotManager.Spawn(3))
	runner.IsBot = nil -- 人間の逃げ手として速度を計算する
	local speed, interval = BotManager.StrengthForTierIndex(5) -- ダイヤ
	bot.SpeedMultiplier, bot.RepathInterval = speed, interval
	GameState.Taggers[bot] = { NoTagBack = other }
	local root, humanoid = GameState.GetRootPart(bot), GameState.GetHumanoid(bot)
	local runnerRoot = GameState.GetRootPart(runner)
	root.Position, runnerRoot.Position = Vector3.new(0, 4, 0), position
	local head = bot.Character:FindFirstChild("Head")
	head.Position = Vector3.new(0, 5.5, 0)
	local hidden, casts, lastOrigin, lastParams = false, 0
	local hiddenX
	RT.workspace._raycast = function(origin, direction, params)
		if params.IgnoreWater then
			casts += 1
			lastOrigin, lastParams = origin, params
			if hidden or (hiddenX and near(origin.X + direction.X, hiddenX)) then
				return { Position = origin }
			end
		end
		return nil
	end
	local destination
	humanoid.MoveTo = function(_, goal) destination = goal end
	GameState.RefreshSpeed(bot)
	BotManager.Tick()
	check("鬼ボットの視線は頭から始まりキャラクターを除外する",
		casts == 1 and lastOrigin == head.Position and lastParams.RespectCanCollide
		and table.find(lastParams.FilterDescendantsInstances, bot.Character)
		and table.find(lastParams.FilterDescendantsInstances, runner.Character))
	hidden = true
	runnerRoot.Position = Vector3.new(30, 4, 0)
	now += Config.BotDecisionInterval + 0.01
	BotManager.Tick()
	check("再計算間隔の途中は視線を撃たず最後の観測位置を維持する",
		casts == 1 and destination == position)
	now += interval
	BotManager.Tick()
	check("遮られた逃げ手の現在位置を使わず最後に見た場所へ向かう",
		bot.GoalReason == "lastSeen" and destination == position)

	root.Position = position
	now += Config.BotDecisionInterval + 0.01
	BotManager.Tick()
	check("最後に見た場所に到着すると鬼ボットはその場で探す",
		bot.GoalReason == "search" and bot.GoalPlayer == runner)
	now += cfg.SearchSeconds - 0.1
	BotManager.Tick()
	check("捜索時間内は隠れている逃げ手の目標を保持する", bot.GoalReason == "search")
	now += 0.2
	BotManager.Tick()
	check("捜索終了後は巡回へ移り、その場に停止しない",
		bot.GoalReason == "patrol" and bot.GoalPlayer == nil and bot.Chase.StartedAt == nil
		and destination ~= nil and (destination - root.Position).Magnitude > cfg.PatrolReach
		and near(humanoid.WalkSpeed, Config.TaggerWalkSpeed * speed * cfg.PatrolSpeedMultiplier))
	local patrolGoal = bot.Chase.PatrolGoal
	now += cfg.PatrolLegSeconds + 0.01
	BotManager.Tick()
	check("巡回先に着けなくても一定時間で次の地点に移る",
		bot.GoalReason == "patrol" and bot.Chase.PatrolGoal ~= patrolGoal)
	hidden, hiddenX = false, runnerRoot.Position.X
	GameState.Taggers[bot].NoTagBack = nil
	now += interval + 0.01
	BotManager.Tick()
	check("巡回中に見えた別の逃げ手を新しい目標として追う",
		bot.GoalReason == "chase" and bot.GoalPlayer == other)
	hiddenX = nil
	GameState.Taggers[bot].NoTagBack = other
	now += interval + 0.01
	BotManager.Tick()
	now += start + ramp + 0.01
	BotManager.Tick()
	check("長く追った鬼ボットの実際の速度に疲れが掛かる",
		near(humanoid.WalkSpeed, Config.TaggerWalkSpeed * speed * (1 - cfg.FatigueMaxReduction)))
	root.Position = runnerRoot.Position
	hiddenX = runnerRoot.Position.X
	GameState.Taggers[bot].NoTagBack = nil
	now += interval + 0.01
	BotManager.Tick()
	check("捜索時に見えた別の逃げ手に切り替わると鬼ボットの速度が戻る",
		bot.GoalPlayer == other and near(humanoid.WalkSpeed, Config.TaggerWalkSpeed * speed))

	local otherRoot = GameState.GetRootPart(other)
	otherRoot.Position = Vector3.new(8, 4, 10)
	otherRoot.AssemblyLinearVelocity = oldHeading
	now += interval + 0.01
	BotManager.Tick()
	otherRoot.AssemblyLinearVelocity = newHeading
	now += interval + 0.01
	BotManager.Tick()
	check("観測した切り返しの誤差が鬼ボットの移動先に反映される",
		bot.GoalAimError and near(destination.X, 8 - 16 * Config.BotPredictionTime + cfg.ErrorDistance))
	now += cfg.ErrorSeconds + 0.01
	BotManager.Tick()
	check("誤差の期限が切れると通常の先読みに戻る",
		not bot.GoalAimError and near(destination.X, 8 - 16 * Config.BotPredictionTime))

	hiddenX = nil
	GameState.GetData(other).SneakUntil = now + 10
	now += interval + 0.01
	BotManager.Tick()
	check("追跡中の相手がしのび足を使うと視界内の別の逃げ手に切り替える", bot.GoalPlayer == runner)
	GameState.GetData(runner).SneakUntil = now + 10
	now += interval + 0.01
	BotManager.Tick()
	check("見えている逃げ手全員がしのび足中でも追跡を続ける", bot.GoalPlayer == runner)
	local castsBeforeInvalidation = casts
	GameState.Taggers[bot].NoTagBack = runner
	now += Config.BotDecisionInterval + 0.01
	BotManager.Tick()
	check("目標が無効になっても次の経路再計算時刻までは視線レイを追加しない",
		bot.GoalPlayer == nil and casts == castsBeforeInvalidation)
	now += interval
	BotManager.Tick()
	check("次の視界確認では無効な目標を除き別の相手を追える", bot.GoalPlayer == other)


	GameState.TimeLeft = Config.TaggerSkills.LateBoost.FinalSeconds
	GameState.RefreshSpeed(bot)
	GameState.GetData(runner).DashUntil = now + Config.Items.Dash.Duration
	GameState.RefreshSpeed(runner)
	check("逃げ手のダッシュ速度は終盤でもダイヤの鬼ボットの通常速度を上回る",
		GameState.GetHumanoid(runner).WalkSpeed > humanoid.WalkSpeed)

	BotManager.DespawnAll()
	GameState.Now, RT.workspace._raycast = oldNow, oldRay
	GameState.Phase, MapBuilder.CurrentMap, GameState.TimeLeft = oldPhase, oldMap, oldTimeLeft
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

	local initialVelocity = Vector3.new(16, 0, 0)
	local noInput = Vector3.new(0, 0, 0)
	local slide = Config.IceVelocity(initialVelocity, noInput, 16, 1)
	local oldSlideSpeed = 16 * math.exp(-0.55)
	check("氷床で入力を離して1秒後は旧設定より速く滑っている",
		slide.X > oldSlideSpeed and slide.X < initialVelocity.X)
	local turn = Config.IceVelocity(initialVelocity, Vector3.new(0, 0, 1), 16, 0.2)
	local oldRetained = math.exp(-2.2 * 0.2)
	check("氷床で直角に入力を変えると旧設定より元の進行方向に近い",
		turn.X > 0 and turn.Z > 0 and turn.Z / turn.X < (1 - oldRetained) / oldRetained)
	local velocity = initialVelocity
	for _ = 1, 30 * 60 do
		velocity = Config.IceVelocity(velocity, noInput, 16, 1 / 60)
	end
	check("氷床でも入力なしで滑り続けると停止する", velocity.Magnitude == 0)

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
	local players = RT.game:GetService("Players")
	local previousLocalPlayer = players.LocalPlayer
	players.LocalPlayer = player
	require("./.build/Slide")()
	players.LocalPlayer = previousLocalPlayer
	local postSimulation = RT.game:GetService("RunService").PostSimulation
	Remotes.StateUpdate.OnClientEvent:_Fire({ Phase = "Round", Participants = { player.UserId } })
	humanoid.MoveDirection = noInput
	humanoid.WalkSpeed = 16
	root.AssemblyLinearVelocity = initialVelocity
	postSimulation:_Fire(1 / 60)
	check("ブーツを使う前は氷床で慣性が適用される", root.AssemblyLinearVelocity.X < initialVelocity.X)

	GameState.ApplyStun(player, 1)
	postSimulation:_Fire(1 / 60)
	local stoppedOnIce = root.AssemblyLinearVelocity.X == 0
	GameState.ClearStun(player)
	postSimulation:_Fire(1 / 60)
	check("人間の氷上滑走はスタン中と解除後に再開しない",
		stoppedOnIce and root.AssemblyLinearVelocity.X == 0)

	local iceBot = BotManager.Spawn(1)[1]
	local iceRoot, iceHumanoid = GameState.GetRootPart(iceBot), GameState.GetHumanoid(iceBot)
	iceHumanoid.MoveDirection = noInput
	iceRoot.AssemblyLinearVelocity = initialVelocity
	local heartbeat = RT.game:GetService("RunService").Heartbeat
	heartbeat:_Fire(1 / 60)
	local slid = iceRoot.AssemblyLinearVelocity.X < initialVelocity.X
	GameState.ApplyStun(iceBot, 1)
	heartbeat:_Fire(1 / 60)
	local botStopped = iceRoot.AssemblyLinearVelocity.X == 0 and iceBot.IceVelocity == nil
	GameState.ClearStun(iceBot)
	heartbeat:_Fire(1 / 60)
	check("ボットの氷上滑走はスタン中と解除後に再開しない",
		slid and botStopped and iceRoot.AssemblyLinearVelocity.X == 0)
	local park = advanceTo("Park")
	player.Character:SetAttribute("IcePatch", true)
	iceBot.Character:SetAttribute("IcePatch", true)
	root.AssemblyLinearVelocity = initialVelocity
	iceRoot.AssemblyLinearVelocity = initialVelocity
	postSimulation:_Fire(1 / 60)
	heartbeat:_Fire(1 / 60)
	check("氷床以外でも氷パッチ上で人間とボットが滑る", park
		and root.AssemblyLinearVelocity.X < initialVelocity.X and iceRoot.AssemblyLinearVelocity.X < initialVelocity.X)
	player.Character:SetAttribute("IcePatch", nil)
	iceBot.Character:SetAttribute("IcePatch", nil)
	BotManager.DespawnAll()
	advanceTo("Ice")

	give("SpikeBoots")
	ItemManager.TryUse(player, 1)
	check("スパイクブーツの効果は5秒間", near(data.SpikeBootsUntil, now + 5) and #data.HeldItems == 0)
	Remotes.ItemUpdate.OnClientEvent:_Fire({ SpikeBootsUntil = data.SpikeBootsServerTime })
	local normalVelocity = Vector3.new(0, 0, 16)
	root.AssemblyLinearVelocity = normalVelocity
	postSimulation:_Fire(1 / 60)
	check("スパイクブーツの効果中は通常移動の速度を維持する",
		(root.AssemblyLinearVelocity - normalVelocity).Magnitude == 0)
	Remotes.StateUpdate.OnClientEvent:_Fire({ Phase = "Intermission" })

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

	local VoltGimmicks = RT.modules.VoltGimmicks
	local effects = volt:FindFirstChild("VoltEffects")
	local area = effects:FindFirstChild("FloorAreas"):GetChildren()[1]
	local marker = effects:FindFirstChild("LightningMarker")
	local bolt = effects:FindFirstChild("LightningBolt")
	now = 200
	local floorWarningAt = now + Config.VoltFloorSafeTime
	local floorActiveAt = floorWarningAt + Config.VoltFloorWarningTime
	local floorSafeAt = floorActiveAt + Config.VoltFloorActiveTime
	local function voltTick(at)
		now = at
		VoltGimmicks.Tick(now)
	end
	root.Position = Vector3.new(area.Position.X, 4, area.Position.Z)
	botRoot.Position = Vector3.new(0, 4, 0)
	VoltGimmicks.Start(now)
	voltTick(floorWarningAt - 0.01)
	check("帯電床：安全中は非表示で感電しない", area.Transparency == 1 and not GameState.IsStunned(player))
	voltTick(floorWarningAt)
	local warningColor = area.Color
	voltTick(floorActiveAt - 0.01)
	check("帯電床：予兆は設定時間だけ表示され、予兆中は感電しない",
		area.Transparency < 1 and not GameState.IsStunned(player))
	voltTick(floorActiveAt)
	check("帯電床：帯電開始時に色が変わり、区画内の逃げ手だけ感電する",
		area.Color ~= warningColor and near(data.StunUntil, now + Config.VoltStunTime)
		and not GameState.IsStunned(bot))
	local floorStunUntil = data.StunUntil
	botRoot.Position = root.Position
	voltTick(floorActiveAt + 0.1)
	check("帯電床：帯電中に入った鬼も感電し、回復待ちの参加者のスタンは延びない",
		GameState.IsStunned(bot) and data.StunUntil == floorStunUntil)

	botRoot.Position = Vector3.new(0, 4, 0)
	voltTick(floorSafeAt - 0.01)
	local activeUntilEnd = area.Transparency < 1
	voltTick(floorSafeAt)
	check("帯電床：設定した帯電時間が終わると安全に戻る", activeUntilEnd and area.Transparency == 1)

	-- 別の周期で絶縁を使い、スタン後無敵が切れた状態で両ギミックを確認する。
	now = 300
	VoltGimmicks.Start(now)
	give("Insulate")
	ItemManager.TryUse(player, 1)
	voltTick(300 + Config.VoltFloorSafeTime)
	voltTick(300 + Config.VoltFloorSafeTime + Config.VoltFloorWarningTime)
	check("帯電床：絶縁を使った参加者は帯電中も感電しない",
		data.InsulateUntil > now and not GameState.IsStunned(player))

	now = 400
	local markerAt = now + Config.VoltLightningInterval
	VoltGimmicks.Start(now)
	voltTick(markerAt - 0.01)
	check("落雷：発生間隔が経過するまではマーカーが出ない", marker.Transparency == 1)
	voltTick(markerAt)
	root.Position = Vector3.new(marker.Position.X, Config.VoltFloorHitHeight + 1, marker.Position.Z)
	botRoot.Position = root.Position + Vector3.new(Config.VoltLightningRadius + 0.01, 0, 0)
	local strikeAt = markerAt + Config.VoltLightningWarningTime
	voltTick(strikeAt - 0.01)
	check("落雷：マーカーの予兆が終わるまで範囲内でも感電しない",
		marker.Transparency < 1 and bolt.Transparency == 1 and not GameState.IsStunned(player))
	voltTick(strikeAt)
	check("落雷：予兆の終了時に光り、円の内側だけ感電する",
		bolt.Transparency < 1 and near(data.StunUntil, now + Config.VoltStunTime)
		and not GameState.IsStunned(bot))
	botRoot.Position = root.Position
	voltTick(strikeAt + 0.01)
	check("落雷：光が残っていても落雷後に入った参加者は感電しない", not GameState.IsStunned(bot))
	voltTick(strikeAt + Config.VoltLightningFlashTime)
	check("落雷：閃光が終わるとマーカーと光が消える", marker.Transparency == 1 and bolt.Transparency == 1)

	now = 500
	VoltGimmicks.Start(now)
	voltTick(500 + Config.VoltLightningInterval)
	root.Position = Vector3.new(marker.Position.X, Config.VoltFloorHitHeight + 1, marker.Position.Z)
	give("Insulate")
	ItemManager.TryUse(player, 1)
	voltTick(500 + Config.VoltLightningInterval + Config.VoltLightningWarningTime)
	check("落雷：絶縁の効果中は円の内側でも感電しない",
		data.InsulateUntil > now and not GameState.IsStunned(player))
	VoltGimmicks.Stop()
	check("ボルト：ラウンド終了処理で表示が消える",
		area.Transparency == 1 and marker.Transparency == 1 and bolt.Transparency == 1)
	GameState.Phase = "Results"
	VoltGimmicks.Start(now)
	voltTick(600)
	check("ボルト：ラウンド外では表示も感電も発生しない",
		area.Transparency == 1 and marker.Transparency == 1 and not GameState.IsStunned(player))

	GameState.Phase = "Round"
	VoltGimmicks.Start(now)
	voltTick(600 + Config.VoltLightningInterval)
	check("帯電床：更新が遅れたときも予兆から始まる", near(area.Transparency, 0.35))
	advanceTo("Ice")
	voltTick(700)
	VoltGimmicks.Start(now)
	voltTick(800)
	check("ボルト：マップ変更で古い落雷を中止し、氷床では開始しない",
		volt.Parent == nil and bolt.Transparency == 1 and not GameState.IsStunned(player)
		and RT.workspace:FindFirstChild(MapBuilder.MapFolderName):FindFirstChild("VoltEffects") == nil)

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
		players.PlayerAdded:_Fire(player)
		PlayerDataStore.Load(player)
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
	local function startTestRound(onIntermission)
		local voted = false
		local round = coroutine.create(RoundManager.Run)
		for _ = 1, Config.IntermissionTime + 2 do
			stepRound(round)
			if onIntermission and not voted and GameState.Phase == "Intermission" then
				onIntermission()
				voted = true
			end
			if GameState.Phase == "Round" then
				return round
			end
		end
		error("テストのラウンドが始まらなかった")
	end
	assert(PlayerDataStore.AddCoins(tagger, Config.Items.Star.Price, false))
	assert(PlayerDataStore.BuyItem(tagger, "Star"))
	assert(PlayerDataStore.SetDeck(tagger, { "Dash", "Star", "Banana", "Shield" }))
	local store = RT.game:GetService("DataStoreService"):GetDataStore("PlayerData_v1")
	local getAsync = store.GetAsync
	PlayerDataStore.Forget(tagger)
	store.GetAsync = function(self, key, options)
		if key == "u_16001" then
			coroutine.yield()
		end
		return getAsync(self, key, options)
	end
	local delayedLoad = coroutine.create(PlayerDataStore.Load)
	assert(coroutine.resume(delayedLoad, tagger))
	store.GetAsync = function(self, key, options)
		if key == "u_16002" then
			error("deck load failed")
		end
		return getAsync(self, key, options)
	end
	local failedLoad = coroutine.create(PlayerDataStore.Load)
	assert(coroutine.resume(failedLoad, runner))
	local round = coroutine.create(RoundManager.Run)
	repeat
		stepRound(round)
	until GameState.Phase == "Intermission"
	for _ = 1, Config.IntermissionTime + 2 do
		stepRound(round)
	end
	check("保存デッキの読み込み中はインターバルのまま組み合わせ判定を待つ",
		GameState.Phase == "Intermission" and PlayerDataStore.GetLoadState(tagger) == "Loading"
		and PlayerDataStore.GetLoadState(runner) == "Loading")
	assert(coroutine.resume(delayedLoad))
	stepRound(round)
	assert(GameState.Phase == "Intermission")
	while coroutine.status(failedLoad) ~= "dead" do
		assert(coroutine.resume(failedLoad))
	end
	store.GetAsync = getAsync
	-- 失敗後にキャッシュが変わっても、組み合わせは既定デッキで判定する。
	PlayerDataStore.Get(runner).Deck = { "Dash", "Star", "Banana", "Shield" }
	stepRound(round)
	check("遅れて読み込んだ保存デッキのコンボが発動し、試合は制限時間いっぱいで始まる",
		GameState.Phase == "Round" and GameState.GetData(tagger).ActiveCombos.StarDash == true
		and GameState.TimeLeft == GameState.ChosenDuration)
	check("保存デッキの読み込みに失敗した参加者は既定デッキで開始する",
		PlayerDataStore.GetLoadState(runner) == "Failed"
		and next(GameState.GetData(runner).ActiveCombos) == nil)
	PlayerDataStore.Load(runner)
	table.insert(roster, extraB)
	check("ラウンド開始後に入室した観戦者にはコンボを付けない",
		not GameState.IsParticipant(extraB) and next(GameState.GetData(extraB).ActiveCombos) == nil)
	table.remove(roster)
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

	-- モード投票とサドンデスを、実際のラウンド進行とタッチ判定で確認する。
	local tally = RoundManager.TallyModeVotes
	local mode, counts = tally({})
	check("モード投票：無投票は通常", mode == "Normal" and counts.Normal == 0 and counts.SuddenDeath == 0)
	mode, counts = tally({ "Normal", "SuddenDeath", "SuddenDeath", {}, false, "Solo" })
	check("モード投票：多数決でサドンデスを選び、想定外の投票を除外",
		mode == "SuddenDeath" and counts.Normal == 1 and counts.SuddenDeath == 2 and counts.Solo == nil)
	check("モード投票：同数は通常", tally({ "Normal", "SuddenDeath" }) == "Normal")
	check("モード投票：通常の票が多ければ通常", tally({ "Normal", "Normal", "SuddenDeath" }) == "Normal")

	local packet
	Remotes.StateUpdate.FireAllClients = function(_, payload) packet = payload end
	Remotes.ModeVote.OnServerEvent:_Fire(tagger, "SuddenDeath")
	check("モード投票：結果表示中の投票は無効", packet == nil)
	Remotes.BotStrengthVote.OnServerEvent:_Fire(tagger, "Strong")
	check("ボットの強さ投票：結果表示中の投票は無効", packet == nil)

	local function voteSuddenDeath()
		local vote = Remotes.ModeVote.OnServerEvent
		vote:_Fire({ IsBot = true }, "Normal")
		vote:_Fire(tagger, "Unknown")
		check("モード投票：新しい投票で票をリセットし、ボット・無効票を拒否",
			packet.ModeVoteCounts.Normal == 0 and packet.ModeVoteCounts.SuddenDeath == 0)
		vote:_Fire(tagger, "Normal")
		vote:_Fire(tagger, "SuddenDeath")
		check("モード投票：投票変更で前の票を置き換える",
			packet.ModeVoteCounts.Normal == 0 and packet.ModeVoteCounts.SuddenDeath == 1)
	end

	Config.BotsEnabled = true
	local savedPrepare = MapBuilder.PrepareRound
	MapBuilder.PrepareRound = function(chosenId)
		local before = packet
		Remotes.ModeVote.OnServerEvent:_Fire(tagger, "SuddenDeath")
		Remotes.BotStrengthVote.OnServerEvent:_Fire(tagger, "Strong")
		Remotes.MapVote.OnServerEvent:_Fire(tagger, Config.MatchMaps[1].Id)
		Remotes.DurationVote.OnServerEvent:_Fire(tagger, Config.MatchDurations[1])
		check("投票：マップ準備中はフェーズ表示がインターバルでも4種類とも受付を終了",
			GameState.Phase == "Intermission" and packet == before)
		return savedPrepare(chosenId)
	end
	round = startTestRound(function()
		tagger:SetAttribute("AdminAdmissionPending", true)
		local before = packet
		Remotes.ModeVote.OnServerEvent:_Fire(tagger, "SuddenDeath")
		check("投票：入室照会中のプレイヤーは受付対象外", packet == before)
		tagger:SetAttribute("AdminAdmissionPending", nil)
		Remotes.BotStrengthVote.OnServerEvent:_Fire(runner, "Normal")
	end)
	MapBuilder.PrepareRound = savedPrepare
	local normalSpeed, normalRepath = BotManager.StrengthForTierIndex(3)
	local normalBots = BotManager.GetActive()
	local normalStrengthOk = #normalBots > 0
	for _, bot in ipairs(normalBots) do
		normalStrengthOk = normalStrengthOk and bot.SpeedMultiplier == normalSpeed and bot.RepathInterval == normalRepath
	end
	check("通常モード：選んだ強さを表示し、補充した全ボットに適用",
		packet.GameMode == "Normal" and packet.BotStrengthName == "ふつう" and normalStrengthOk)
	now += GameState.ChosenDuration
	stepRound(round)

	-- 人間とボットが混在しても最初の鬼は人間から選ぶ。
	round = startTestRound(voteSuddenDeath)
	local hunter = GameState.TaggerList()[1]
	check("サドンデス：ボット混在時も人間2人以上なら人間の鬼が1人",
		#BotManager.GetActive() > 0 and #GameState.TaggerList() == 1 and not BotManager.IsBot(hunter)
		and packet.Mode == RT.modules.MatchSession.Mode and packet.GameMode == "SuddenDeath"
		and packet.RunnersLeft == GameState.CountParticipants() - 1)
	check("おまかせ：平均段位でボットを補充したラウンドは段位名を併記",
		packet.BotStrengthName:sub(1, #"おまかせ（") == "おまかせ（")
	now += GameState.ChosenDuration
	stepRound(round)

	Config.BotsEnabled = false
	round = startTestRound(voteSuddenDeath)
	hunter = GameState.TaggerList()[1]
	local left, last
	for player in pairs(GameState.Uncaught) do
		if left then last = player else left = player end
	end
	place(GameState.GetRootPart(hunter), CFrame.new(0, 0, 0))
	place(GameState.GetRootPart(left), CFrame.new(0, 0, -2))
	place(GameState.GetRootPart(last), CFrame.new(25, 0, 0))
	now += Config.TagCooldown
	local leftData = GameState.GetData(left)
	leftData.StarUntil = now + 1
	RoundManager.TryTag()
	check("サドンデス：スターで無効になったタッチでは脱落も加点も起きない",
		GameState.IsParticipant(left) and GameState.Uncaught[left] and hunter:GetAttribute("RoundRP") == 0)
	leftData.StarUntil = 0
	leftData.ActiveCombos.HighJumpGrapple = true
	GameState.RefreshSpeed(left)
	local outgoing = { IsBot = true, UserId = math.huge }
	GameState.Taggers[outgoing] = { Since = 0 }
	RoundManager.TryTag()
	check("タッチで鬼一覧が変わっても解除済みの鬼では判定しない", not GameState.IsTagger(outgoing))
	GameState.ClearData(outgoing)
	check("脱落して観戦に移ると発動中のコンボと速度効果を解除する",
		next(leftData.ActiveCombos) == nil and GameState.GetHumanoid(left).WalkSpeed == Config.NormalWalkSpeed)
	check("サドンデス：タッチで逃げ手だけが脱落し、鬼と残り人数が正しい",
		#GameState.TaggerList() == 1 and GameState.IsTagger(hunter)
		and not GameState.IsParticipant(left) and RoundManager.IsEliminated(left)
		and packet.RunnersLeft == 1 and not GameState.Uncaught[left] and GameState.Uncaught[last])
	check("サドンデス：タッチで鬼に6RP、脱落者に4RPと試合統計を加算",
		hunter:GetAttribute("RoundRP") == 6 and left:GetAttribute("RoundRP") == 4
		and hunter:GetAttribute("RoundTags") == 1 and left:GetAttribute("RoundCaught") == 1
		and GameState.TagCounts[left] == 1)
	place(GameState.GetRootPart(last), CFrame.new(0, 0, -2))
	stepRound(round)
	check("サドンデス：全員タッチで鬼の勝ち、鬼に全員捕獲14RP",
		GameState.Phase == "Results" and GameState.Message == "鬼の勝ち！"
		and #GameState.Winners == 0 and hunter:GetAttribute("RoundRP") == 6 * 2 + 14
		and last:GetAttribute("RoundRP") == 4 and GameState.Results[1].Status == "最後の鬼"
		and GameState.Results[2].Status == "脱落")

	round = startTestRound(voteSuddenDeath)
	hunter = GameState.TaggerList()[1]
	left = next(GameState.Uncaught)
	last = next(GameState.Uncaught, left)
	ZoneManager.OnEliminate(left)
	now += GameState.ChosenDuration
	stepRound(round)
	check("サドンデス：時間切れで生存者が優勝し20RP、ゾーン脱落者は0RP",
		GameState.Phase == "Results" and #GameState.Winners == 1 and GameState.Winners[1] == last
		and GameState.Results[1].Status == "優勝" and GameState.Results[1].Coins == Config.CoinRewards.Champion
		and last:GetAttribute("RoundRP") == 20 and left:GetAttribute("RoundRP") == 0
		and hunter:GetAttribute("RoundRP") == 0)

	round = startTestRound(voteSuddenDeath)
	hunter = GameState.TaggerList()[1]
	left = next(GameState.Uncaught)
	last = next(GameState.Uncaught, left)
	ZoneManager.OnEliminate(left)
	RoundManager.ApplyTag(hunter, last)
	check("サドンデス：ゾーン脱落を全員捕獲に含めない",
		GameState.Uncaught[left] and not GameState.Uncaught[last]
		and hunter:GetAttribute("RoundRP") == 6 and left:GetAttribute("RoundRP") == 0)
	stepRound(round)
	check("サドンデス：ゾーン脱落とタッチで逃げ手が全滅しても鬼の勝ち",
		GameState.Phase == "Results" and GameState.Message == "鬼の勝ち！")

	round = startTestRound(voteSuddenDeath)
	hunter = GameState.TaggerList()[1]
	local skillUpdates = {}
	local skillRemote = Remotes.TaggerSkillUpdate
	Remotes.TaggerSkillUpdate = { FireClient = function(_, recipient, info) skillUpdates[recipient] = info end }
	local taggerSkills = RT.modules.TaggerSkills
	taggerSkills.Use(hunter, "Smell")
	assert(skillUpdates[hunter].Smell)
	players.PlayerRemoving:_Fire(hunter)
	check("鬼が退出すると嗅覚を解除してから試合データを削除する",
		skillUpdates[hunter].Smell == nil and GameState.AllData()[hunter] == nil)
	local survivor = next(GameState.Participants)
	local eliminated = next(GameState.Participants, survivor)
	ZoneManager.OnEliminate(eliminated)
	stepRound(round)
	check("サドンデス：鬼の退出で最後の逃げ手が優勝し20RPを獲得する",
		GameState.Phase == "Results" and #GameState.TaggerList() == 0
		and #GameState.Winners == 1 and GameState.Winners[1] == survivor
		and survivor:GetAttribute("RoundRP") == 20 and eliminated:GetAttribute("RoundRP") == 0
		and #GameState.Results == 2)
	PlayerDataStore.Load(hunter)

	round = startTestRound(voteSuddenDeath)
	hunter = GameState.TaggerList()[1]
	left = next(GameState.Uncaught)
	check("サドンデス：管理画面でも鬼を交代できない",
		not RoundManager.SetAdminTagger(left) and not GameState.IsTagger(left)
		and GameState.IsTagger(hunter) and #GameState.TaggerList() == 1 and packet.RunnersLeft == 2)
	local role = GameState.Taggers[hunter]
	taggerSkills.Use(hunter, "Smell")
	local readyAt = GameState.GetData(hunter).TaggerSkillReadyAt.Smell
	local savedRaycast = RT.workspace._raycast
	local ground = RT.Instance.new("Part")
	ground.CanCollide = true
	local center = ZoneManager.GetCenter()
	RT.workspace._raycast = function()
		return { Position = center, Instance = ground, Normal = Vector3.new(0, 1, 0) }
	end
	local hunterRoot = GameState.GetRootPart(hunter)
	place(hunterRoot, CFrame.new(center + Vector3.new(0, Config.FallEliminateY - 100, 0)))
	local oldMap, getPlatforms = MapBuilder.CurrentMap, MapBuilder.GetSkyPlatforms
	local platforms = RT.Instance.new("Folder")
	MapBuilder.CurrentMap = "Sky"
	MapBuilder.GetSkyPlatforms = function() return platforms end
	RoundManager.CheckSkyFalls()
	MapBuilder.CurrentMap, MapBuilder.GetSkyPlatforms = oldMap, getPlatforms
	check("サドンデス：落下した鬼は役割とスキル待ち時間を保ってゾーン中央に復帰する",
		GameState.Taggers[hunter] == role and GameState.IsParticipant(hunter)
		and not RoundManager.IsEliminated(hunter)
		and near(hunterRoot.Position.X, center.X) and near(hunterRoot.Position.Z, center.Z)
		and hunterRoot.Position.Y > center.Y and readyAt ~= nil
		and GameState.GetData(hunter).TaggerSkillReadyAt.Smell == readyAt)
	local oldCharacter = hunter.Character
	GameState.GetHumanoid(hunter).Health = 0
	local respawned = makePlayer(16999, CFrame.new(100, 0, 100)).Character
	hunter.CharacterRemoving:_Fire(oldCharacter)
	hunter.Character = respawned
	hunter.CharacterAdded:_Fire(respawned)
	oldCharacter:Destroy()
	RT.workspace._raycast = savedRaycast
	local respawnRoot = GameState.GetRootPart(hunter)
	check("サドンデス：人間の鬼の死亡後も、新しいキャラクターは同じ鬼として中央に復活する",
		GameState.IsAlive(hunter) and GameState.Taggers[hunter] == role
		and GameState.GetData(hunter).TaggerSkillReadyAt.Smell == readyAt
		and near(respawnRoot.Position.X, center.X) and near(respawnRoot.Position.Z, center.Z)
		and respawned:FindFirstChild(TaggerLook.HighlightName) ~= nil)
	now += GameState.ChosenDuration
	stepRound(round)

	round = startTestRound(voteSuddenDeath)
	local remainingRunner = next(GameState.Uncaught)
	local endingTagger = GameState.TaggerList()[1]
	taggerSkills.Use(endingTagger, "Smell")
	assert(skillUpdates[endingTagger].Smell)
	assert(RoundManager.RequestEnd())
	stepRound(round)
	check("管理者の強制終了で鬼本人の嗅覚表示を解除する",
		skillUpdates[endingTagger].Smell == nil and GameState.GetData(endingTagger).TaggerSmellUntil == 0)
	Remotes.TaggerSkillUpdate = skillRemote
	check("サドンデス：管理者の途中終了を時間切れの優勝・生存RPとして扱わない",
		GameState.Phase == "Results" and #GameState.Winners == 0
		and remainingRunner:GetAttribute("RoundRP") == 0)

	local session = RT.modules.MatchSession
	local previousSessionMode = session.Mode
	session.Mode = "Solo"
	players.GetPlayers = function() return { tagger } end
	round = startTestRound(voteSuddenDeath)
	hunter = GameState.TaggerList()[1]
	local speed, repath = BotManager.StrengthForTierIndex(#Config.BotStrengthByTier)
	check("サドンデス：ソロでは最上位のボットが鬼で、実際の速度と経路間隔に反映",
		BotManager.IsBot(hunter) and #GameState.TaggerList() == 1 and not hunter.SoloCap
		and hunter.SpeedMultiplier == speed and hunter.RepathInterval == repath
		and near(GameState.GetHumanoid(hunter).WalkSpeed, Config.TaggerWalkSpeed * speed))
	local soloRunnersCapped = true
	for _, bot in ipairs(BotManager.GetActive()) do
		if bot ~= hunter then
			soloRunnersCapped = soloRunnersCapped and bot.SoloCap and bot.RepathInterval == nil
		end
	end
	check("サドンデス：ソロの逃げ手ボットは従来の強さを使う",
		soloRunnersCapped and #BotManager.GetActive() == Config.SoloBotCount)
	now += GameState.ChosenDuration
	stepRound(round)

	round = startTestRound(function()
		Remotes.ModeVote.OnServerEvent:_Fire(tagger, "SuddenDeath")
		local vote = Remotes.BotStrengthVote.OnServerEvent
		local before = packet
		vote:_Fire({ IsBot = true }, "Strong")
		vote:_Fire(tagger, "Unknown")
		check("ボットの強さ投票：ボットと無効な選択肢を拒否", packet == before)
		vote:_Fire(tagger, "Strong")
		vote:_Fire(tagger, "Weak")
		check("ボットの強さ投票：投票変更は前の票を置き換える",
			packet.BotStrengthVoteCounts.Strong == 0 and packet.BotStrengthVoteCounts.Weak == 1)
	end)
	hunter = GameState.TaggerList()[1]
	local weakSpeed, weakRepath = BotManager.StrengthForTierIndex(1)
	local weakRunners = true
	local nextHunter
	for _, bot in ipairs(BotManager.GetActive()) do
		if bot ~= hunter then
			nextHunter = bot
			weakRunners = weakRunners and bot.SpeedMultiplier == weakSpeed
				and bot.RepathInterval == weakRepath and bot.SoloCap
		end
	end
	check("サドンデス：よわいを選んでも鬼ボットだけ最上位",
		GameState.ChosenBotStrength == "Weak" and packet.BotStrengthName == "よわい"
		and BotManager.IsBot(hunter) and hunter.SpeedMultiplier == speed and hunter.RepathInterval == repath
		and not hunter.SoloCap and near(GameState.GetHumanoid(hunter).WalkSpeed, Config.TaggerWalkSpeed * speed)
		and nextHunter ~= nil and weakRunners)
	local oldCharacter = hunter.Character
	local botRole = GameState.Taggers[hunter]
	GameState.GetData(hunter).TaggerSkillReadyAt.Smell = now + 100
	local botReadyAt = GameState.GetData(hunter).TaggerSkillReadyAt.Smell
	GameState.GetHumanoid(hunter).Health = 0
	stepRound(round)
	check("サドンデス：鬼ボットが死亡しても同じ鬼・最上位の強さ・クールダウンで復活する",
		hunter.Character ~= oldCharacter and GameState.IsAlive(hunter)
		and GameState.IsParticipant(hunter) and GameState.Taggers[hunter] == botRole
		and hunter.SpeedMultiplier == speed and hunter.RepathInterval == repath and not hunter.SoloCap
		and GameState.GetData(hunter).TaggerSkillReadyAt.Smell == botReadyAt)
	now += GameState.ChosenDuration
	stepRound(round)

	local soloBotCount = Config.SoloBotCount
	Config.SoloBotCount = 0
	round = startTestRound(voteSuddenDeath)
	Config.SoloBotCount = soloBotCount
	hunter = GameState.TaggerList()[1]
	check("サドンデス：通常の補充で候補がいないソロでも最上位の鬼ボットを追加",
		BotManager.IsBot(hunter) and hunter.RepathInterval == repath and #BotManager.GetActive() == 1
		and GameState.CountParticipants() == 2 and packet.RunnersLeft == 1)
	check("ボットの強さ投票：次のラウンドで票をリセットし無投票ならおまかせ",
		packet.BotStrengthVoteCounts.Weak == 0 and packet.BotStrengthVoteCounts.Strong == 0
		and GameState.ChosenBotStrength == "Auto" and packet.BotStrengthName == "おまかせ")
	now += GameState.ChosenDuration
	stepRound(round)
	session.Mode = previousSessionMode
	Remotes.StateUpdate.FireAllClients = nil
	GameState.ChosenMode = Config.SuddenDeath.NormalId

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
	local tiers = {
		{ "B", 7, { "Bastet", "Thoth", "Khepri", "Hathor", "Geb", "Nut", "Bes", "Taweret" } },
		{ "A", 5, { "Sobek", "Sekhmet", "Isis", "Maat", "Serqet", "Apis" } },
		{ "S", 2, { "Horus", "Osiris", "Set", "Atum", "Apophis", "Hapy" } },
		{ "SS", 0.5, { "Anubis", "Ra", "Amun", "Ptah" } },
	}
	local definitionCount = 0
	for _ in pairs(Config.Beasts) do
		definitionCount += 1
	end
	local index, totalWeight = 0, 0
	for _, tier in ipairs(tiers) do
		local name, weight, ids = tier[1], tier[2], tier[3]
		for _, id in ipairs(ids) do
			index += 1
			local def = Config.Beasts[id]
			local low = totalWeight
			totalWeight += def and def.Weight or 0
			check(id .. " の定義・レア度・抽選帯", Config.BeastOrder[index] == id and def
				and type(def.DisplayName) == "string" and #def.DisplayName > 0
				and type(def.Description) == "string" and #def.Description > 0
				and def.Tier == name and def.Weight == weight
				and PlayerDataStore.PickBeast(low / 100) == id
				and PlayerDataStore.PickBeast((totalWeight - 0.001) / 100) == id)
			local model = RT.modules.BeastModels.Build(id, RT.CFrame.new(), 0.4)
			local blocks = model and model:GetChildren() or {}
			local decorative = #blocks > 0
			for _, block in ipairs(blocks) do
				decorative = decorative and block.Anchored and not block.CanCollide and not block.CanTouch and not block.CanQuery
			end
			check(id .. " のブロックは固定され、判定に影響しない", decorative)
			if model then
				model:Destroy()
			end
		end
	end
	check("召喚獣は24体で抽選確率の合計は100%", definitionCount == 24 and #Config.BeastOrder == 24 and totalWeight == 100)
	check("抽選範囲の両端でバステトとプタハを引ける",
		PlayerDataStore.PickBeast(0) == "Bastet" and PlayerDataStore.PickBeast(1 - 1e-12) == "Ptah")

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
	local equipped = PlayerDataStore.SetEquippedBeast(player, result.Id)
	check("所持している召喚獣を装備し、Getで確認できる",
		equipped and PlayerDataStore.Get(player).EquippedBeast == result.Id)
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
	local previousTimeLeft = GameState.TimeLeft
	GameState.TimeLeft = GameState.ChosenDuration
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
	equip("Khepri")
	local khepriData = GameState.GetData(player)
	khepriData.ActiveCombos.StarDash = true
	check("コンボ：ケプリのダッシュには持続ボーナスが付かない",
		ItemManager.UseBeast(player) and near(khepriData.DashUntil, now + Config.Beasts.Khepri.Duration))

	local originalFireClient = Remotes.ItemUpdate.FireClient
	local comboUpdates = {}
	Remotes.ItemUpdate.FireClient = function(_, recipient, info)
		comboUpdates[recipient] = info.ActiveCombos
	end
	ItemManager.DeliverPendingItems()
	local playerCombos = comboUpdates[player]
	local enemyCombos = comboUpdates[enemy]
	check("コンボ：試合開始時の ItemUpdate は本人の発動中の組み合わせだけを送る",
		playerCombos and #playerCombos == 1 and playerCombos[1] == Config.ItemComboText(Config.ItemCombos[4])
		and enemyCombos and #enemyCombos == 0)
	Remotes.ItemUpdate.FireClient = originalFireClient

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

	for _, participant in ipairs({ player, enemy, ally, far }) do
		GameState.Taggers[participant] = nil
	end
	GameState.Taggers[enemy] = { Since = 0 }
	GameState.RefreshSpeed(player)
	GameState.RefreshSpeed(enemy)

	equip("Geb")
	check("ゲブは転倒扱いにならず、移動とジャンプが止まる", ItemManager.UseBeast(player)
		and GameState.IsProne(player) and not GameState.IsDowned(player)
		and humanoid.WalkSpeed == 0 and humanoid.JumpHeight == 0)
	RoundManager.TryTag()
	check("ゲブの伏せ中は接触しても捕獲されない", GameState.IsTagger(enemy) and not GameState.IsTagger(player))
	now += Config.Beasts.Geb.Duration
	ItemManager.Tick()
	check("ゲブの終了で伏せ姿勢と移動速度が戻る", not GameState.IsProne(player)
		and not player.Character:GetAttribute("BananaDowned") and humanoid.WalkSpeed == Config.NormalWalkSpeed)
	RoundManager.TryTag()
	check("ゲブ終了後の接触では捕獲される", GameState.IsTagger(player))
	GameState.Taggers[player] = nil
	GameState.Taggers[enemy] = { Since = 0 }

	equip("Bes")
	GameState.GetData(player).ZoneStamina = 3
	GameState.TryDown(player)
	GameState.ApplyStun(player, 5)
	check("ベスは転倒・スタン中にも使え、即座に回復して2秒無敵になる", ItemManager.UseBeast(player)
		and not GameState.IsDowned(player) and not GameState.IsStunned(player)
		and GameState.GetData(player).InvulnerableUntil == now + 2 and GameState.GetData(player).ZoneStamina == 3)

	equip("Atum")
	local priorMap = RT.workspace:GetAttribute("CurrentMap")
	RT.workspace:SetAttribute("CurrentMap", "Sky")
	ZoneManager.Start(120)
	local beforeWarp = root.Position
	local floor = RT.Instance.new("Part")
	local obstruction = RT.Instance.new("Part")
	local oldRay, oldBounds = RT.workspace._raycast, RT.workspace._bounds
	RT.workspace._raycast = function(origin)
		return { Instance = floor, Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0) }
	end
	floor.CanCollide = false
	check("アトゥムは Sky のゾーン内に衝突可能な足場がなければ移動も消費もしない",
		not ItemManager.UseBeast(player) and root.Position == beforeWarp and not GameState.GetData(player).BeastUsed)
	ZoneManager.Stop()
	RT.workspace:SetAttribute("CurrentMap", "Arena")
	ZoneManager.Start(120)
	local warpCenter = ZoneManager.GetCenter()
	floor.CanCollide, obstruction.CanCollide = true, true
	RT.workspace._raycast = function(origin)
		assert(origin.Y > warpCenter.Y)
		return { Instance = floor, Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0) }
	end
	RT.workspace._bounds = function(frame)
		if near(frame.Position.X, warpCenter.X) and near(frame.Position.Z, warpCenter.Z) then
			return { obstruction }
		end
		return {}
	end
	check("アトゥムは中央が塞がれていれば近くへ移動して消費する", ItemManager.UseBeast(player)
		and near((root.Position - Vector3.new(warpCenter.X, root.Position.Y, warpCenter.Z)).Magnitude, 4)
		and GameState.GetData(player).BeastUsed == "Atum" and GameState.GetData(player).ZoneReturns == 0)
	RT.workspace._raycast, RT.workspace._bounds = oldRay, oldBounds
	ZoneManager.Stop()
	RT.workspace:SetAttribute("CurrentMap", priorMap)

	equip("Apophis")
	farHumanoid.Health = 0
	GameState.RefreshSpeed(player)
	local stopped = ItemManager.UseBeast(player)
	for _, participant in ipairs({ enemy, ally }) do
		stopped = stopped and GameState.GetData(participant).FrozenUntil == now + 4
			and GameState.GetRootPart(participant).Anchored and GameState.GetHumanoid(participant).WalkSpeed == 0
	end
	check("アペプは鬼を含む生存中の召喚者以外を4秒止める", stopped
		and GameState.GetData(far).FrozenUntil == 0 and GameState.GetData(player).FrozenUntil == 0
		and not root.Anchored and humanoid.WalkSpeed == Config.NormalWalkSpeed)
	now += 4
	ItemManager.Tick()
	check("アペプ終了後には鬼も移動できる", not enemyRoot.Anchored and enemyHumanoid.WalkSpeed == Config.TaggerWalkSpeed)
	farHumanoid.Health = 100

	equip("Ptah")
	local inventory = GameState.GetData(player).HeldItems
	check("プタハはデッキからアイテムを1つ付与する", ItemManager.UseBeast(player) and #inventory == 1
		and table.find(Config.DefaultDeck, inventory[1]) ~= nil)

	equip("Ptah")
	local fullData = GameState.GetData(player)
	local slots = GameState.GetItemSlots(player)
	fullData.HeldItems = table.create(slots, "Dash")
	fullData.HeldExpireAt = table.create(slots, now + 1)
	check("プタハは満枠なら付与の規則どおり入れ替える", ItemManager.UseBeast(player)
		and #fullData.HeldItems == slots and fullData.HeldExpireAt[slots] == 0)

	local function place(part, x, z)
		part.Position = Vector3.new(x, 4, z)
		part.CFrame = RT.CFrame.new(part.Position)
		part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end

	equip("Nut")
	place(root, 0, 0)
	humanoid.FloorMaterial = RT.Enum.Material.Air
	check("ヌトは上と前に飛び出す", ItemManager.UseBeast(player)
		and root.AssemblyLinearVelocity.Y == Config.Beasts.Nut.LaunchUpSpeed and root.AssemblyLinearVelocity.Z < 0)
	root.AssemblyLinearVelocity = Vector3.new(0, -50, 0)
	ItemManager.Tick()
	check("ヌトの滑空中は落下速度が制限され前進する",
		root.AssemblyLinearVelocity.Y == -Config.Beasts.Nut.FallSpeed
		and root.AssemblyLinearVelocity.Z == -Config.Beasts.Nut.GlideSpeed)
	humanoid.FloorMaterial = RT.Enum.Material.Grass
	ItemManager.Tick()
	check("ヌトは着地で滑空が終了する", GameState.GetData(player).BeastGlideUntil == 0
		and not player.Character:GetAttribute("BeastGlideVelocity"))

	equip("Taweret")
	place(enemyRoot, 8, 0)
	place(GameState.GetRootPart(ally), -6, 0)
	place(farRoot, 12, 0)
	GameState.Taggers[far] = { Since = 0 }
	check("タウエレトは半径10以内の鬼だけを押す", ItemManager.UseBeast(player)
		and enemyRoot.AssemblyLinearVelocity.X == Config.Beasts.Taweret.KnockbackSpeed
		and farRoot.AssemblyLinearVelocity.X == 0 and GameState.GetRootPart(ally).AssemblyLinearVelocity.X == 0)

	equip("Hapy")
	check("ハピは半径14以内の鬼と逃げ手を強く押す", ItemManager.UseBeast(player)
		and enemyRoot.AssemblyLinearVelocity.X == Config.Beasts.Hapy.KnockbackSpeed
		and farRoot.AssemblyLinearVelocity.X == Config.Beasts.Hapy.KnockbackSpeed
		and GameState.GetRootPart(ally).AssemblyLinearVelocity.X == -Config.Beasts.Hapy.KnockbackSpeed)

	equip("Serqet")
	place(enemyRoot, 0, -8)
	place(farRoot, 0, -12)
	check("セルケトは前方で最も近い鬼だけをスタンさせる", ItemManager.UseBeast(player)
		and GameState.GetData(enemy).StunUntil == now + Config.Beasts.Serqet.StunTime
		and not GameState.IsStunned(far))
	GameState.ClearStun(enemy)
	GameState.RefreshSpeed(enemy)

	equip("Apis")
	place(enemyRoot, 3, 0)
	check("アピスは走る速度が上がる", ItemManager.UseBeast(player)
		and near(humanoid.WalkSpeed, Config.NormalWalkSpeed * Config.Beasts.Apis.SpeedMultiplier))
	ItemManager.Tick()
	check("アピスは近い鬼を弾く", enemyRoot.AssemblyLinearVelocity.X == Config.Beasts.Apis.KnockbackSpeed)
	place(enemyRoot, 3, 0)
	ItemManager.Tick()
	check("アピスは同じ鬼を連続で弾かない", enemyRoot.AssemblyLinearVelocity.X == 0)
	now += Config.Beasts.Apis.HitCooldown
	ItemManager.Tick()
	check("アピスは待機時間後に同じ鬼を再び弾く", enemyRoot.AssemblyLinearVelocity.X == Config.Beasts.Apis.KnockbackSpeed)

	equip("Maat")
	root.Transparency = 0.4
	local oldPosition = root.Position
	check("マアトは固定された分身を残して本体を透明にする", ItemManager.UseBeast(player)
		and root.Transparency == 1 and GameState.GetData(player).BeastDecoyPosition == oldPosition
		and RT.workspace:FindFirstChild("MaatDecoy") ~= nil)
	local previousBotMap = MapBuilder.CurrentMap
	MapBuilder.CurrentMap = "Arena"
	GameState.Taggers[ally] = { Since = 0 }
	local chasingBot = BotManager.Spawn(1)[1]
	GameState.Taggers[chasingBot] = { Since = 0 }
	place(root, oldPosition.X + 20, oldPosition.Z + 20)
	local chased
	GameState.GetHumanoid(chasingBot).MoveTo = function(_, position) chased = position end
	BotManager.Tick()
	check("マアトの透明化中は鬼ボットが本体ではなく分身の位置へ向かう",
		chased and near(chased.X, oldPosition.X) and near(chased.Z, oldPosition.Z))
	now += 6
	ItemManager.Tick()
	check("マアト終了後は元の透明度に戻り、分身が消える", root.Transparency == 0.4
		and GameState.GetData(player).BeastDecoyPosition == nil and RT.workspace:FindFirstChild("MaatDecoy") == nil)

	BotManager.Tick()
	check("マアト終了後は鬼ボットが本人の位置へ向かう",
		chased and near(chased.X, root.Position.X) and near(chased.Z, root.Position.Z))
	BotManager.DespawnAll()
	GameState.Taggers[ally] = nil
	MapBuilder.CurrentMap = previousBotMap

	equip("Maat")
	ItemManager.UseBeast(player)
	humanoid.Health = 0
	ItemManager.Tick()
	check("死亡でマアトの透明化と分身が解除される", root.Transparency == 0.4
		and RT.workspace:FindFirstChild("MaatDecoy") == nil)
	humanoid.Health = 100

	equip("Amun")
	check("アメンは透明化と無敵と速度上昇を同時に付与する", ItemManager.UseBeast(player)
		and root.Transparency == 1 and GameState.GetData(player).InvulnerableUntil == now + 10
		and near(humanoid.WalkSpeed, Config.NormalWalkSpeed * 1.15))

	ItemManager.Stop()
	check("ラウンド終了でアメンの透明化が解除される", root.Transparency == 0.4)
	for _, entrantPlayer in ipairs({ player, enemy, ally, far }) do
		entrantPlayer.Character:Destroy()
		GameState.Participants[entrantPlayer] = nil
		GameState.Taggers[entrantPlayer] = nil
		GameState.ClearData(entrantPlayer)
		PlayerDataStore.Forget(entrantPlayer)
		entrantPlayer:Destroy()
	end
	GameState.Phase = "Waiting"
	GameState.TimeLeft = previousTimeLeft
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

---------------------------------------------------------------------
-- ロビーの召喚獣追従
---------------------------------------------------------------------
do
	local lobbyMap = RT.Instance.new("Model")
	lobbyMap.Name = "LobbyMap"
	lobbyMap.Parent = RT.workspace
	local BeastFollower = require("./.build/BeastFollower")
	local folder = RT.workspace:FindFirstChild("LobbyBeastFollowers")
	local heartbeat = RT.game:GetService("RunService").Heartbeat
	local settings = Config.LobbyBeastFollower

	local function addRoot(character, x)
		local root = RT.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Position = Vector3.new(x, 3, 0)
		root.Size = Vector3.new(2, 2, 1)
		root.CFrame = RT.CFrame.new(root.Position)
		root.Parent = character
		return root
	end

	local player = RT.Instance.new("Player")
	player.UserId = 19008
	player.Character = RT.Instance.new("Model")
	local root = addRoot(player.Character, 0)
	local store = RT.game:GetService("DataStoreService"):GetDataStore("PlayerData_v1")
	store:SetAsync("u_19008", { Beasts = { Bastet = true, Thoth = true }, EquippedBeast = "Bastet" })
	RT.workspace._raycast = function(origin)
		return { Position = Vector3.new(origin.X, 0, origin.Z) }
	end

	local target = BeastFollower.GetTargetPosition(Vector3.new(5, 3, 10), Vector3.new(0.3, 0.5, -0.4))
	check("追従の目標は傾きを除いた正面の反対へ指定距離だけ計算する",
		near(target.X, 5 - 0.6 * settings.FollowDistance) and near(target.Y, 3)
		and near(target.Z, 10 + 0.8 * settings.FollowDistance))
	BeastFollower.SetEquipped(player, nil)
	check("装備なしでは追従モデルが出ない", #folder:GetChildren() == 0)

	local data = PlayerDataStore.Load(player)
	BeastFollower.SetEquipped(player, data.EquippedBeast)
	local first = folder:FindFirstChild("Bastet")
	check("保存済みの装備で持ち主付きの追従モデルが出る",
		first and first:GetAttribute("OwnerUserId") == player.UserId and #folder:GetChildren() == 1)

	local ok, equipped = PlayerDataStore.SetEquippedBeast(player, "Thoth")
	BeastFollower.SetEquipped(player, equipped.EquippedBeast)
	local second = folder:FindFirstChild("Thoth")
	check("装備変更で古い追従モデルを片付ける", ok and not first.Parent and second and #folder:GetChildren() == 1)

	root.Position = Vector3.new(8, 3, 0)
	heartbeat:_Fire(0.1)
	local position = second.WorldPivot.Position
	check("通常の移動は補間し、浮き沈みしても足元は床より上にある",
		position.X > 0 and position.X < 8 and near(position.Z, settings.FollowDistance)
		and position.Y > 0 and not near(position.Y, settings.GroundClearance)
		and near(second.WorldPivot.LookVector.Z, -1))
	for _ = 1, 120 do
		heartbeat:_Fire(1 / 60)
	end
	check("プレイヤーが止まると追従モデルは目標の水平位置に収まる",
		near(second.WorldPivot.Position.X, 8) and near(second.WorldPivot.Position.Z, settings.FollowDistance))

	root.Position = Vector3.new(8 + settings.SnapDistance + 1, 3, 0)
	heartbeat:_Fire(0.1)
	check("テレポートで離れた場合は近くに寄せ直す", near(second.WorldPivot.Position.X, root.Position.X))

	player.CharacterRemoving:_Fire(player.Character)
	local newCharacter = RT.Instance.new("Model")
	player.Character = newCharacter
	player.CharacterAdded:_Fire(newCharacter)
	check("リスポーン時に古いモデルを消し、ルートができるまで待つ", not second.Parent and #folder:GetChildren() == 0)
	addRoot(newCharacter, 10)
	heartbeat:_Fire(0.1)
	local respawned = folder:FindFirstChild("Thoth")
	check("リスポーン後は新しいキャラクターに付け直す",
		respawned and #folder:GetChildren() == 1 and near(respawned.WorldPivot.Position.X, 10))

	local cleared, unequipped = PlayerDataStore.SetEquippedBeast(player, "")
	BeastFollower.SetEquipped(player, unequipped.EquippedBeast)
	check("召喚獣の装備解除をGetで確認できる",
		cleared and PlayerDataStore.Get(player).EquippedBeast == nil)
	local reloaded = PlayerDataStore.Load(player)
	check("装備解除を保存するとモデルだけ消え、所持は残る",
		cleared and #folder:GetChildren() == 0 and not respawned.Parent
		and reloaded.EquippedBeast == nil and reloaded.Beasts.Thoth)

	BeastFollower.SetEquipped(player, "Thoth")
	BeastFollower.Remove(player)
	player.CharacterAdded:_Fire(newCharacter)
	heartbeat:_Fire(0.1)
	check("退場時はモデルと追従を片付ける", #folder:GetChildren() == 0)
	PlayerDataStore.Forget(player)
	RT.workspace._raycast = nil
	lobbyMap:Destroy()
end

-- ロビーの管理リモートと、同じ BAN ストアを使う試合側の管理リモート。
do
	RT.modules.AdminService = require("./.build/AdminService")
	local LobbyAdmin = require("./.build/LobbyAdmin")
	local AdminManager = require("./.build/AdminManager")
	local players = RT.game:GetService("Players")
	local stores = RT.game:GetService("DataStoreService")
	local bans = stores:GetDataStore("AdminBansV1")
	local ranks = stores:GetDataStore(Config.RankDataStoreName)
	local leaderboard = stores:GetOrderedDataStore(Config.RankLeaderboardStoreName)
	local inventory = stores:GetDataStore("PlayerData_v1")
	local originalGetPlayers = players.GetPlayers
	local function makePlayer(userId, name)
		local player = RT.Instance.new("Player")
		player.UserId = userId
		player.Name = name
		player.Parent = players
		player.Kick = function(self, reason)
			self.KickReason = reason
			self.Parent = nil
		end
		local character = RT.Instance.new("Model")
		local root = RT.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Position = Vector3.new(userId % 10 * 10, 0, 0)
		root.CFrame = RT.CFrame.new(root.Position.X, 0, 0)
		root.Parent = character
		player.Character = character
		return player, root
	end
	local owner, ownerRoot = makePlayer(28101, "Owner")
	local admin = makePlayer(28102, "Admin")
	local target, targetRoot = makePlayer(28103, "Target")
	RT.game.CreatorType = RT.Enum.CreatorType.User
	RT.game.CreatorId = owner.UserId
	table.insert(Config.AdminUserIds, admin.UserId)
	local roster = { owner, admin, target }
	players.GetPlayers = function()
		local present = {}
		for _, player in ipairs(roster) do
			if player.Parent == players then
				table.insert(present, player)
			end
		end
		return present
	end

	local remote = RT.Instance.new("RemoteEvent")
	local notify = RT.Instance.new("RemoteEvent")
	local reply, announcement, updates, displayedRP = nil, nil, 0, 125
	local ready = true
	remote.FireClient = function(_, _, payload) reply = payload end
	notify.FireAllClients = function(_, text) announcement = text end
	local admit = LobbyAdmin.Init({
		Remote = remote,
		Notify = notify,
		RankStore = ranks,
		IsLoaded = function() return ready end,
		GetRP = function() return displayedRP end,
		ShowRP = function(_, rp) displayedRP = rp end,
		WriteLeaderboard = function(key, rp)
			leaderboard:UpdateAsync(key, function(old) return math.max(old or 0, rp) end)
			return true
		end,
		SendData = function() updates += 1 end,
	})
	local function request(actor, action, first, second)
		reply = nil
		remote.OnServerEvent:_Fire(actor, action, first, second)
		return reply
	end

	local pendingReply, pendingAttribute
	local getBan = bans.GetAsync
	bans.GetAsync = function(self, key, options)
		pendingAttribute = owner:GetAttribute("AdminAdmissionPending")
		pendingReply = request(owner, "Announce", "pending")
		return getBan(self, key, options)
	end
	admit(owner)
	bans.GetAsync = getBan
	admit(admin)
	admit(target)
	check("管理者は所有者または許可リストに登録されたユーザー", owner:GetAttribute("IsAdmin")
		and admin:GetAttribute("IsAdmin") and target:GetAttribute("IsAdmin") == false)
	check("BAN 確認中は所有者でも管理操作を要求できない",
		pendingAttribute == true and pendingReply == nil and announcement == nil)

	local noReplies = true
	for _, action in ipairs({ "Kick", "Ban", "Unban", "ListBans", "NextBans", "Announce",
		"Bring", "GoTo", "AwardCoins", "AwardRP", "GrantBeast", "Status" }) do
		local first = action == "Announce" and "unauthorized" or owner.UserId
		local second = action == "GrantBeast" and "Thoth" or 25
		noReplies = request(target, action, first, second) == nil and noReplies
	end
	check("一般プレイヤーは全管理リクエストで拒否され、副作用も発生しない",
		noReplies and not owner.KickReason and not bans:GetAsync(tostring(owner.UserId))
			and not inventory:GetAsync("u_" .. owner.UserId) and not ranks:GetAsync(tostring(owner.UserId))
			and updates == 0 and announcement == nil and ownerRoot.Position.X == 10 and targetRoot.Position.X == 30)

	local key = tostring(target.UserId)
	local inventoryKey = "u_" .. key
	ranks:SetAsync(key, { RP = 125, Survived = 4, Tagged = 3 })
	local rejected = true
	for _, action in ipairs({ "AwardCoins", "AwardRP" }) do
		for _, value in ipairs({ 0, -1, 1.5, 1000001, math.huge, 0/0, "5", {} }) do
			local result = request(owner, action, target.UserId, value)
			rejected = result and result.Status.History[1]:find("失敗") ~= nil and rejected
		end
	end
	for _, value in ipairs({ 12, "", "MissingBeast", {} }) do
		local result = request(owner, "GrantBeast", target.UserId, value)
		rejected = result and result.Status.History[1]:find("失敗") ~= nil and rejected
	end
	check("付与の不正な整数・型・召喚獣 ID は保存されない",
		rejected and not inventory:GetAsync(inventoryKey) and ranks:GetAsync(key).RP == 125 and not leaderboard:GetAsync(key))

	ready = false
	local loading = request(owner, "AwardCoins", target.UserId, 1)
	check("ロード中のプレイヤーには付与しない",
		loading.Message:find("読み込み中") and not inventory:GetAsync(inventoryKey))
	ready = true

	request(owner, "AwardCoins", target.UserId, 1000000)
	local savedInventory = inventory:GetAsync(inventoryKey)
	check("コイン付与は上限の整数を保存し、勝利数を変更しない",
		savedInventory.Coins == 1000000 and savedInventory.Wins == 0 and updates == 1)
	local rpReply = request(admin, "AwardRP", target.UserId, 75)
	local savedRank = ranks:GetAsync(key)
	check("RP 付与は RankV1・表示・ランキングを更新し、既存の試合成績を保持する",
		savedRank.RP == 200 and savedRank.Survived == 4 and savedRank.Tagged == 3
			and displayedRP == 200 and leaderboard:GetAsync(key) == 200
			and rpReply.Status.History[1]:find("75 RP") and rpReply.Status.Players[3].RP == 200)
	request(owner, "GrantBeast", target.UserId, "Thoth")
	local duplicate = request(admin, "GrantBeast", target.UserId, "Thoth")
	savedInventory = inventory:GetAsync(inventoryKey)
	check("召喚獣付与は所持を保存して表示を更新し、重複時はメッセージを返す",
		savedInventory.Beasts.Thoth and not savedInventory.EquippedBeast and updates == 2
			and duplicate.Message:find("すでに所持"))

	request(owner, "Announce", "notice")
	request(owner, "Bring", target.UserId)
	local brought = targetRoot.Position.X == 14
	targetRoot.CFrame = RT.CFrame.new(40, 0, 0)
	request(owner, "GoTo", target.UserId)
	check("お知らせでフィルター済みの文面を配信し、呼び寄せと移動ができる",
		announcement == "[filtered] notice" and brought and ownerRoot.Position.X == 44)
	check("ロビーは試合専用のコマンドを受け付けない", request(owner, "SetBots", not Config.BotsEnabled) == nil)

	local concurrentUnban
	local setBan = bans.SetAsync
	bans.SetAsync = function(self, banKey, value)
		concurrentUnban = request(admin, "Unban", target.UserId)
		return setBan(self, banKey, value)
	end
	local banReply = request(owner, "Ban", target.UserId, "test reason")
	bans.SetAsync = setBan
	check("同じ対象を別の管理者が同時に BAN 解除しようとすると拒否される",
		concurrentUnban.Message:find("更新中"))
	local record = bans:GetAsync(key)
	check("ロビーで BAN すると共有ストアに理由を保存し、その場でキックする",
		record and record.Reason == "[filtered] test reason" and target.KickReason:find("test reason")
			and #banReply.Status.Players == 2)

	local reconnect = makePlayer(target.UserId, target.Name)
	check("BAN 済みユーザーはロビー再入場時にキックされる",
		not admit(reconnect) and reconnect.KickReason:find("test reason")
			and reconnect:GetAttribute("AdminAdmissionPending") and not reconnect:GetAttribute("IsAdmin"))

	AdminManager.Init()
	local matchReply
	Remotes.AdminRequest.FireClient = function(_, _, payload) matchReply = payload end
	players.PlayerAdded:_Fire(owner)
	local matchJoin = makePlayer(target.UserId, target.Name)
	players.PlayerAdded:_Fire(matchJoin)
	check("試合側もロビーで保存した BAN を使って入室を拒否する",
		matchJoin.KickReason:find("test reason"))
	local botsEnabled = Config.BotsEnabled
	Remotes.AdminRequest.OnServerEvent:_Fire(owner, "SetBots", not botsEnabled)
	check("試合専用のボット設定は引き続き試合側から操作できる",
		Config.BotsEnabled ~= botsEnabled and matchReply.Status.BotsEnabled == not botsEnabled)
	Config.BotsEnabled = botsEnabled
	Remotes.AdminRequest.FireClient = nil

	local seeded = {}
	for userId = 28201, 28225 do
		local banKey = tostring(userId)
		table.insert(seeded, banKey)
		bans:SetAsync(banKey, {})
	end
	local page1 = request(owner, "ListBans").Bans
	local page2 = request(owner, "NextBans").Bans
	check("BAN 一覧を25件ずつページ送りできる",
		page1.HasNext and #page1.UserIds == 25 and page1.UserIds[1] == target.UserId
			and not page2.HasNext and #page2.UserIds == 1)
	local unbanReply = request(owner, "Unban", target.UserId)
	local unbanned = makePlayer(target.UserId, target.Name)
	check("ロビーで BAN 解除すると保存が消え、再入場できる",
		unbanReply.Unbanned == target.UserId and not bans:GetAsync(key) and admit(unbanned))
	request(owner, "Kick", admin.UserId)
	check("管理者のキックは BAN を保存しない", admin.KickReason and not bans:GetAsync(tostring(admin.UserId)))

	local unavailable = makePlayer(owner.UserId, owner.Name)
	local attempts, remainedPending = 0, true
	bans.GetAsync = function()
		attempts += 1
		remainedPending = remainedPending and unavailable:GetAttribute("AdminAdmissionPending")
			and request(unavailable, "Announce", "pending") == nil
		error("BAN store unavailable")
	end
	local admitted = admit(unavailable)
	bans.GetAsync = getBan
	check("BAN 照会失敗時は管理操作を拒否し、3回確認できなければ入場を拒否する",
		attempts == 3 and remainedPending and not admitted and unavailable.KickReason
		and unavailable:GetAttribute("AdminAdmissionPending") and not unavailable:GetAttribute("IsAdmin"))

	for _, banKey in ipairs(seeded) do
		bans:RemoveAsync(banKey)
	end
	players.GetPlayers = originalGetPlayers
	PlayerDataStore.Forget(target)
	table.remove(Config.AdminUserIds)
	RT.game.CreatorType = nil
	RT.game.CreatorId = nil
end

require("./beast_trade")(check)

---------------------------------------------------------------------
-- ロビーショップ：設定、購入と装備、アイテムボックスの引き継ぎ
---------------------------------------------------------------------

do
	local CharacterTrail = require("./.build/CharacterTrail")
	check("トレイル：3種の表示順", table.concat(Config.TrailOrder, ",") == "PurpleGlow,GoldStar,RedFlame")
	for _, entry in ipairs({ { "PurpleGlow", 300 }, { "GoldStar", 800 }, { "RedFlame", 2000 } }) do
		local id, price = entry[1], entry[2]
		local def = Config.Trails[id]
		check("トレイル：価格と見た目の設定 " .. id, def and def.Price == price
			and type(def.DisplayName) == "string" and def.Lifetime > 0
			and def.ColorStart and def.ColorEnd and def.TransparencyStart >= 0
			and def.LightEmission >= 0 and def.AttachmentHeight > 0)
	end
	local ready = true
	for _, key in ipairs(Config.ShopProductOrder) do
		ready = ready and Config.ShopProductId(key) == 0
	end
	check("Robux：商品 ID がすべて未設定なので準備中", ready and #Config.ShopProductOrder == 3)
	check("Robux：対象外のキーからは購入 ID を取得できない", Config.ShopProductId("PurpleGlow") == 0)
	local product = Config.Monetization.ItemBox
	local originalId = product.ProductId
	product.ProductId = 12345
	check("Robux：設定済みの製品 ID は購入に使える", Config.ShopProductId("ItemBox") == 12345)
	product.ProductId = originalId

	local player = { UserId = 887401 }
	local original = PlayerDataStore.Load(player)
	check("ショップ：旧データでは未所持、装備未設定、未受領なし",
		next(original.Trails) == nil and original.EquippedTrail == nil and original.ItemBoxes == 0)
	PlayerDataStore.AddCoins(player, 400, false)
	local ok, reason, data = PlayerDataStore.BuyTrail(player, "GoldStar")
	check("トレイル：残高不足では所持も残高も変わらない", not ok and reason
		and data.Coins == 400 and next(data.Trails) == nil)
	ok, reason, data = PlayerDataStore.BuyTrail(player, "Unknown")
	check("トレイル：未定義の ID は理由つきで拒否", not ok and reason and data.Coins == 400)
	ok, _, data = PlayerDataStore.BuyTrail(player, "PurpleGlow")
	check("トレイル：購入すると残高が減って所持に入る", ok and data.Coins == 100 and data.Trails.PurpleGlow)
	ok, reason, data = PlayerDataStore.BuyTrail(player, "PurpleGlow")
	check("トレイル：二重購入では理由を返し残高も維持", not ok and reason == "もう持っています" and data.Coins == 100)
	check("トレイル：未所持の装備を拒否", not PlayerDataStore.SetEquippedTrail(player, "RedFlame"))
	ok, data = PlayerDataStore.SetEquippedTrail(player, "PurpleGlow")
	check("トレイル：装備したコイントレイルがパスより優先", ok and data.EquippedTrail == "PurpleGlow"
		and CharacterTrail.Resolve(data, true) == Config.Trails.PurpleGlow)
	ok, data = PlayerDataStore.SetEquippedTrail(player, "Sparkle")
	check("トレイル：Sparkle の見た目はパス所持時だけ適用", ok and data.EquippedTrail == "Sparkle"
		and CharacterTrail.Resolve(data, true) == Config.Monetization.SparkleTrail
		and CharacterTrail.Resolve(data, false) == nil)
	ok, data = PlayerDataStore.SetEquippedTrail(player, "")
	check("トレイル：明示的に外すとパス所持者もトレイルなし", ok and data.EquippedTrail == ""
		and CharacterTrail.Resolve(data, true) == nil)
	local normalized = PlayerDataStore.Normalize({ Trails = { Unknown = true }, EquippedTrail = "PurpleGlow" })
	check("トレイル：Normalize が不明な所持 ID と未所持の装備を落とす",
		next(normalized.Trails) == nil and normalized.EquippedTrail == nil)
	check("トレイル：装備未設定のパス所持者には従来の見た目を適用",
		CharacterTrail.Resolve(normalized, true) == Config.Monetization.SparkleTrail)

	local added = PlayerDataStore.AddItemBox(player)
	local addedAgain = PlayerDataStore.AddItemBox(player)
	check("アイテムボックス：購入回数を永続保存", added and addedAgain and PlayerDataStore.Load(player).ItemBoxes == 2)
	local count, taken = PlayerDataStore.TakeItemBoxes(player)
	check("アイテムボックス：全数を取り出して保存上の残数をゼロにする",
		taken and count == 2 and PlayerDataStore.Load(player).ItemBoxes == 0)
	PlayerDataStore.AddItemBox(player)
	PlayerDataStore.AddItemBox(player)
	count, taken = PlayerDataStore.TakeItemBoxes(player, 1)
	check("アイテムボックス：付与中に買い足した分は残る",
		taken and count == 1 and PlayerDataStore.Load(player).ItemBoxes == 1)
	RT.DataStoreShouldFail = true
	added = PlayerDataStore.AddItemBox(player)
	count, taken = PlayerDataStore.TakeItemBoxes(player)
	RT.DataStoreShouldFail = false
	check("アイテムボックス：保存失敗時は成功扱いにせず残数を保つ",
		not added and count == 0 and not taken and PlayerDataStore.Load(player).ItemBoxes == 1)
	PlayerDataStore.Forget(player)
end

do
	local buyer = RT.Instance.new("Player")
	buyer.UserId = 887402
	buyer.Parent = RT.game:GetService("Players")
	local other = { UserId = 887403 }
	PlayerDataStore.Load(buyer)
	PlayerDataStore.Load(other)
	local saved, added = PlayerDataStore.AddItemBox(buyer, "review-receipt")
	PlayerDataStore.Forget(buyer)
	PlayerDataStore.Load(buyer)
	local duplicateSaved, duplicateAdded = PlayerDataStore.AddItemBox(buyer, "review-receipt")
	check("アイテムボックス：同じレシートを再入室後に処理しても1個だけ保存し他人の残数は変えない",
		saved and added and duplicateSaved and not duplicateAdded
		and PlayerDataStore.Get(buyer).ItemBoxes == 1 and PlayerDataStore.Get(other).ItemBoxes == 0)

	local previousPhase = GameState.Phase
	GameState.Phase = "Round"
	ItemManager.Start()
	ItemManager.DeliverSavedItemBoxes(buyer)
	check("アイテムボックス：観戦中は受け取らず保存に残す",
		PlayerDataStore.Get(buyer).ItemBoxes == 1 and #GameState.GetData(buyer).HeldItems == 0)
	GameState.Participants[buyer] = true

	local store = RT.game:GetService("DataStoreService"):GetDataStore("PlayerData_v1")
	local updateAsync = store.UpdateAsync
	local interrupted = false
	store.UpdateAsync = function(self, key, transform)
		local data = updateAsync(self, key, transform)
		if not interrupted then
			interrupted = true
			GameState.Participants[buyer] = nil
		end
		return data
	end
	ItemManager.DeliverSavedItemBoxes(buyer)
	store.UpdateAsync = updateAsync
	check("アイテムボックス：保存中に参加資格を失った場合は未受領数へ戻す",
		interrupted and PlayerDataStore.Load(buyer).ItemBoxes == 1 and #GameState.GetData(buyer).HeldItems == 0)

	GameState.Participants[buyer] = true
	RT.DataStoreShouldFail = true
	ItemManager.DeliverSavedItemBoxes(buyer)
	RT.DataStoreShouldFail = false
	check("アイテムボックス：保存に失敗したら試合内で付与せず再試行できる",
		PlayerDataStore.Load(buyer).ItemBoxes == 1 and #GameState.GetData(buyer).HeldItems == 0)

	local responseLost = false
	store.UpdateAsync = function(self, key, transform)
		local data = updateAsync(self, key, transform)
		if not responseLost then
			responseLost = true
			assert(PlayerDataStore.AddItemBox(buyer, "second-review-receipt"))
			error("saved before response was lost")
		end
		return data
	end
	ItemManager.DeliverSavedItemBoxes(buyer)
	store.UpdateAsync = updateAsync
	local data = PlayerDataStore.Load(buyer)
	check("アイテムボックス：保存後の応答消失と買い足しが重なっても両方を受領できる",
		responseLost and data.ItemBoxes == 0 and next(data.ItemBoxClaims) == nil
		and #GameState.GetData(buyer).HeldItems == 2
		and PlayerDataStore.AddItemBox(buyer, "second-review-receipt")
		and PlayerDataStore.Get(buyer).ItemBoxes == 0)

	GameState.ClearData(buyer)
	GameState.Participants[buyer] = nil
	GameState.Phase = previousPhase
	ItemManager.Stop()
	PlayerDataStore.Forget(buyer)
	PlayerDataStore.Forget(other)
end

-- アイテム追加と鬼ボットのしのび足判定
do
	local bomb, boomerang = Config.Items.SlowBomb, Config.Items.Boomerang
	check("スロウボムの定義はB・150コイン、半径10・減速3秒・寿命20秒",
		bomb.Id == "SlowBomb" and bomb.Tier == "B" and bomb.Price == 150
		and bomb.SpawnWeight == 1 and bomb.CanTaggerUse and bomb.Radius == 10
		and bomb.SlowTime == 3 and bomb.Duration == 20 and bomb.SlowSpeed > 0
		and bomb.SlowSpeed < Config.NormalWalkSpeed)
	check("ブーメランの定義はA・400コイン、スタン1.5秒・射程30",
		boomerang.Id == "Boomerang" and boomerang.Tier == "A" and boomerang.Price == 400
		and boomerang.SpawnWeight == 1 and boomerang.CanTaggerUse == false
		and boomerang.StunTime == 1.5 and boomerang.Range == 30
		and boomerang.Speed > 0 and boomerang.HitRadius > 0)
	local seen, unique = {}, true
	for _, id in ipairs(Config.ItemOrder) do
		unique = unique and not seen[id]
		seen[id] = true
	end
	check("アイテム一覧には新規2種を重複なく含む", unique and seen.SlowBomb and seen.Boomerang)
	local exclusives = {}
	for id, def in pairs(Config.Items) do
		if def.ExclusiveMap then
			exclusives[id] = def.ExclusiveMap
		end
	end
	local expected = { Phase = "Cave", SpikeBoots = "Ice", Insulate = "Volt", SafetyLine = "Sky" }
	local sameMaps = true
	for id, map in pairs(expected) do
		sameMaps = sameMaps and exclusives[id] == map and not seen[id]
		exclusives[id] = nil
	end
	check("ダンジョン固有アイテムは従来の4種", sameMaps and next(exclusives) == nil)

	local buyer = { UserId = 887403 }
	PlayerDataStore.Load(buyer)
	PlayerDataStore.AddCoins(buyer, 550, false)
	local bombBought = PlayerDataStore.BuyItem(buyer, bomb.Id)
	local boomerangBought = PlayerDataStore.BuyItem(buyer, boomerang.Id)
	local deck = { bomb.Id, boomerang.Id, "Dash", "Banana" }
	local saved = PlayerDataStore.SetDeck(buyer, deck)
	local reloaded = PlayerDataStore.Load(buyer)
	check("購入した新規2種をデッキに保存して再読込できる", bombBought and boomerangBought and saved
		and reloaded.Coins == 0 and reloaded.Deck[1] == bomb.Id and reloaded.Deck[2] == boomerang.Id)
	local pool = ItemManager.GetFieldPool(reloaded.Deck, "Cave")
	local defaultPool = ItemManager.GetFieldPool(Config.DefaultDeck, "Cave")
	check("フィールドの箱はデッキ入りの新規アイテムを抽選する", table.find(pool, bomb.Id)
		and table.find(pool, boomerang.Id) and table.find(pool, "Phase")
		and not table.find(defaultPool, bomb.Id) and not table.find(defaultPool, boomerang.Id))

	local slowDistance, throwDistance = Config.BotSlowBombDistance, Config.BotBoomerangDistance
	check("鬼と逃げ手のボットは相手が近ければボムを使う",
		BotManager.ShouldUseItem(bomb.Id, true, slowDistance)
		and BotManager.ShouldUseItem(bomb.Id, false, slowDistance)
		and not BotManager.ShouldUseItem(bomb.Id, false, slowDistance + 1))
	check("ブーメランは鬼が近い逃げ手ボットだけが使う",
		BotManager.ShouldUseItem(boomerang.Id, false, throwDistance)
		and not BotManager.ShouldUseItem(boomerang.Id, false, throwDistance + 1)
		and not BotManager.ShouldUseItem(boomerang.Id, true, throwDistance))
	local closeRunner = { X = 2, Sneaking = true }
	local farRunner = { X = 5 }
	local ctx = { Role = "Tagger", Runners = { closeRunner, farRunner } }
	local _, _, _, target = BotManager.ChooseGoal(ctx)
	check("鬼ボットは近くのしのび足より遠くの見える逃げ手を狙う", target == farRunner)
	farRunner.Sneaking = true
	_, _, _, target = BotManager.ChooseGoal(ctx)
	check("全員がしのび足中なら鬼ボットは最も近い逃げ手を狙う", target == closeRunner)

	local function makeParticipant(position)
		local player = { IsBot = true, Character = RT.Instance.new("Model") }
		local root = RT.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Position = position
		root.CFrame = RT.CFrame.new(position)
		root.Parent = player.Character
		local humanoid = RT.Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.Parent = player.Character
		GameState.Participants[player] = true
		return player, root, humanoid
	end

	local oldClock, oldPhase = GameState.Now, GameState.Phase
	local oldParticipants, oldTaggers = GameState.Participants, GameState.Taggers
	local now = 400
	GameState.Now = function() return now end
	GameState.Phase = "Round"
	GameState.Participants, GameState.Taggers = {}, {}
	local origin = Vector3.new(0, 4, 0)
	local thrower, _, throwerHumanoid = makeParticipant(origin)
	local victim, victimRoot, victimHumanoid = makeParticipant(Vector3.new(11, 4, 0))
	local other, otherRoot, otherHumanoid = makeParticipant(Vector3.new(0, 4, 11))
	local throwerData = GameState.GetData(thrower)
	local victimData = GameState.GetData(victim)
	local function use(id)
		now += Config.UseItemCooldown + 0.01
		throwerData.HeldItems, throwerData.HeldExpireAt = { id }, { 0 }
		ItemManager.TryUse(thrower, 1)
	end
	local function findPart(name)
		return RT.workspace:FindFirstChild("SpawnedItems"):FindFirstChild(name)
	end

	ItemManager.Start()
	GameState.Taggers[thrower] = { Since = now }
	use(bomb.Id)
	local placed = findPart(bomb.Id)
	check("鬼も足元にボムを設置できる", placed and placed.Position.Y < origin.Y and #throwerData.HeldItems == 0)
	check("ボムの判定は設置者を除く",
		not ItemManager.IsSlowBombTarget(thrower, thrower, placed.Position, bomb.Radius))
	ItemManager.Tick()
	check("ボムは本人と範囲外の参加者では起爆しない", placed.Parent ~= nil and victimData.SlowUntil == 0)
	victimRoot.Position = Vector3.new(4, 4, 0)
	otherRoot.Position = Vector3.new(0, 4, 4)
	GameState.ApplySlow(victim, "Glue")
	now += 0.5
	ItemManager.Tick()
	check("範囲内の全員を減速させて消え、本人は減速しない", placed.Parent == nil
		and near(victimData.SlowUntil, now + 3) and near(GameState.GetData(other).SlowUntil, now + 3)
		and otherHumanoid.WalkSpeed == bomb.SlowSpeed and throwerData.SlowUntil == 0)
	check("減速が重なると有効な設定のうち最も遅い速度が適用される",
		victimHumanoid.WalkSpeed == Config.Items.Glue.SlowSpeed)
	now = victimData.SlowEffects.Glue
	ItemManager.Tick()
	check("ねばねば罠が先に切れてもボムの減速は残る", victimHumanoid.WalkSpeed == bomb.SlowSpeed)
	now = victimData.SlowUntil
	ItemManager.Tick()
	check("ボムの減速が切れると通常速度に戻る",
		victimData.SlowUntil == 0 and victimHumanoid.WalkSpeed == Config.NormalWalkSpeed)
	victimRoot.Position = Vector3.new(11, 4, 0)
	otherRoot.Position = Vector3.new(0, 4, 11)
	use(bomb.Id)
	placed = findPart(bomb.Id)
	now += bomb.Duration
	ItemManager.Tick()
	check("起爆しなかったボムは寿命で消える", placed.Parent == nil)

	use(boomerang.Id)
	check("鬼はブーメランを投げられない", not findPart(boomerang.Id) and #throwerData.HeldItems == 1)
	GameState.Taggers[thrower] = nil
	use(boomerang.Id)
	local projectile = findPart(boomerang.Id)
	local direction = Vector3.new(0, 0, -1)
	check("ブーメランの当たり判定は投擲者を除く",
		ItemManager.GetBoomerangHitDistance(thrower, thrower, origin, direction, 5, boomerang.HitRadius) == nil)
	now += 0.1
	ItemManager.Tick()
	check("ブーメランはTickで前方に進む", near(projectile.Position.Z, -boomerang.Speed * 0.1))
	victimRoot.Position = Vector3.new(0, 4, -12)
	otherRoot.Position = Vector3.new(0, 4, -20)
	now += boomerang.Range / boomerang.Speed
	ItemManager.Tick()
	check("ブーメランは移動区間で最初に当たった相手だけを1.5秒スタンさせて消える",
		projectile.Parent == nil and near(victimData.StunUntil, now + 1.5)
		and victimHumanoid.WalkSpeed == 0 and GameState.GetData(other).StunUntil == 0
		and throwerData.StunUntil == 0 and throwerHumanoid.WalkSpeed ~= 0)
	victimRoot.Position = Vector3.new(0, 4, -boomerang.Range - boomerang.HitRadius - 1)
	otherRoot.Position = Vector3.new(0, 4, 11)
	use(boomerang.Id)
	projectile = findPart(boomerang.Id)
	now += 2
	ItemManager.Tick()
	check("射程外の相手には届かず、射程でブーメランが消える",
		projectile.Parent == nil and victimData.StunUntil == 0)
	use(bomb.Id)
	placed = findPart(bomb.Id)
	use(boomerang.Id)
	projectile = findPart(boomerang.Id)
	ItemManager.Stop()
	check("ラウンド終了でボムと飛行中のブーメランが消える", placed.Parent == nil and projectile.Parent == nil)

	for _, player in ipairs({ thrower, victim, other }) do
		GameState.ClearData(player)
		player.Character:Destroy()
	end
	GameState.Now, GameState.Phase = oldClock, oldPhase
	GameState.Participants, GameState.Taggers = oldParticipants, oldTaggers
end

-- 段階Gのアイテム定義と実際の使用経路
do
	local definitions = {
		RecoveryDrink = { "B", true },
		Teleporter = { "A", true, HeightOffset = 3 },
		Giant = { "A", true, Duration = 6, Scale = 1.5, ReachMultiplier = 1.5, KnockbackMultiplier = 0.5 },
		Shrink = { "B", true, Duration = 6, Scale = 0.6 },
		Grapple = { "A", true, Range = 40, Speed = 90, ArrivalDistance = 1, SurfaceOffset = 2,
			TopNormalMinY = 0.65, PlatformAimDrop = 0.2, MinPlatformRise = 1, Timeout = 0.8 },
		Swap = { "S", true, HeightOffset = 1 },
		FakeBox = { "B", true, Duration = 20, StunTime = 2 },
		IceBomb = { "B", true, Duration = 5, Radius = 8, Thickness = 0.12, HeightTolerance = 1.5 },
		Thunder = { "S", false, Range = 30, StunTime = 2, FlashDuration = 0.2, FlashHeight = 18, FlashWidth = 0.6 },
		Reflect = { "A", false, Duration = 4, PushSpeed = 44, LiftSpeed = 9, GraceTime = 1.5 },
	}
	local prices = { B = 150, A = 400, S = 900 }
	for id, expected in pairs(definitions) do
		local def = Config.Items[id]
		local valid = def and def.Id == id and def.Tier == expected[1] and def.Price == prices[expected[1]]
			and def.SpawnWeight == 1 and def.CanTaggerUse == expected[2]
		for key, value in pairs(expected) do
			if type(key) == "string" then
				valid = valid and def[key] == value
			end
		end
		check(id .. " のレア度・価格・効果の定義", valid)
	end

	local counts, seen, complete = { B = 0, A = 0, S = 0 }, {}, true
	for _, id in ipairs(Config.ItemOrder) do
		local def = Config.Items[id]
		complete = complete and def ~= nil and not def.ExclusiveMap and not seen[id]
		seen[id] = true
		if def and counts[def.Tier] then
			counts[def.Tier] += 1
		end
	end
	for id, def in pairs(Config.Items) do
		complete = complete and (def.ExclusiveMap ~= nil or seen[id])
	end
	check("基本アイテム28種を重複なく表示し、内訳はB11・A12・S5", complete and #Config.ItemOrder == 28
		and counts.B == 11 and counts.A == 12 and counts.S == 5)

	local buyer = { UserId = 887404 }
	PlayerDataStore.Load(buyer)
	PlayerDataStore.AddCoins(buyer, 1450, false)
	local deck = { "RecoveryDrink", "Giant", "Swap", "Dash" }
	local bought = PlayerDataStore.BuyItem(buyer, deck[1]) and PlayerDataStore.BuyItem(buyer, deck[2])
		and PlayerDataStore.BuyItem(buyer, deck[3])
	local saved = PlayerDataStore.SetDeck(buyer, deck)
	local reloaded = PlayerDataStore.Load(buyer)
	check("新規3種を4枠デッキに保存して再読込できる", bought and saved and Config.DeckSize == 4
		and table.concat(reloaded.Deck, ",") == table.concat(deck, ","))
	PlayerDataStore.Forget(buyer)

	for _, rule in ipairs({
		{ "Giant", true, Config.BotGiantDistance },
		{ "Shrink", false, Config.BotShrinkDistance },
		{ "Swap", false, Config.BotSwapDistance },
		{ "FakeBox", true, Config.BotBananaDistance },
		{ "IceBomb", true, Config.BotIceBombDistance },
		{ "Thunder", false, Config.Items.Thunder.Range },
		{ "Reflect", false, Config.BotShieldDistance },
	}) do
		local id, taggerAllowed, distance = table.unpack(rule)
		check(id .. " のボット使用距離と役割", BotManager.ShouldUseItem(id, false, distance)
			and BotManager.ShouldUseItem(id, true, distance) == taggerAllowed
			and not BotManager.ShouldUseItem(id, false, distance + 1))
	end
	check("距離だけで判断できない3種をボットは使用しない",
		not BotManager.ShouldUseItem("RecoveryDrink", false, 0)
		and not BotManager.ShouldUseItem("Teleporter", false, 0)
		and not BotManager.ShouldUseItem("Grapple", true, 0))

	local oldClock, oldPhase = GameState.Now, GameState.Phase
	local oldParticipants, oldTaggers = GameState.Participants, GameState.Taggers
	local oldRaycast = RT.workspace._raycast
	local now = 700
	GameState.Now = function() return now end
	GameState.Phase = "Round"
	GameState.Participants, GameState.Taggers = {}, {}
	local function makeParticipant(id, position)
		local player = { IsBot = true, UserId = id, DisplayName = tostring(id), Character = RT.Instance.new("Model") }
		local root = RT.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Position = position
		root.CFrame = RT.CFrame.new(position)
		root.Parent = player.Character
		local humanoid = RT.Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.HipHeight = 2
		humanoid.FloorMaterial = RT.Enum.Material.Concrete
		humanoid.Parent = player.Character
		GameState.Participants[player] = true
		GameState.RegisterCharacter(player, player.Character)
		return player, root, humanoid
	end
	local origin = Vector3.new(0, 3, 0)
	local player, root, humanoid = makeParticipant(-701, origin)
	local target, targetRoot, targetHumanoid = makeParticipant(-702, Vector3.new(5, 3, 0))
	local other, otherRoot, otherHumanoid = makeParticipant(-703, Vector3.new(40, 3, 0))
	local data = GameState.GetData(player)
	local targetData = GameState.GetData(target)
	local function use(id, inventory)
		now += Config.UseItemCooldown + 0.01
		if inventory then
			data.HeldItems, data.HeldExpireAt = inventory, {}
		elseif id then
			data.HeldItems, data.HeldExpireAt = { id }, { 0 }
		end
		ItemManager.TryUse(player, 1)
	end

	local map = RT.workspace:FindFirstChild(MapBuilder.MapFolderName)
	local temporaryMap
	if not map then
		temporaryMap = RT.Instance.new("Folder")
		temporaryMap.Name = MapBuilder.MapFolderName
		temporaryMap.Parent = RT.workspace
		map = temporaryMap
	end
	local function safeFloor(position, direction, params)
		if direction.Y < 0 and params.FilterDescendantsInstances[1] == map then
			return { Position = Vector3.new(position.X, 0, position.Z) }
		end
	end
	RT.workspace._raycast = safeFloor
	ItemManager.Start()
	humanoid.FloorMaterial = RT.Enum.Material.Air
	use("Teleporter")
	check("テレポーターは空中では記録せず、アイテムを保持する",
		data.TeleporterMarker == nil and data.HeldItems[1] == "Teleporter")
	humanoid.FloorMaterial = RT.Enum.Material.Concrete
	data.ZoneStamina = 1
	GameState.Taggers[player] = { Since = now }
	use(nil, { "Teleporter", "RecoveryDrink" })
	check("テレポーターの1回目は現在のCFrameを記録して消費しない",
		data.TeleporterMarker == root.CFrame and #data.HeldItems == 2)
	now += Config.UseItemCooldown + 0.01
	ItemManager.TryUse(player, 2)
	check("鬼も回復ドリンクで全回復しテレポーターの記録は残る", data.ZoneStamina == Config.ZoneStaminaMax
		and #data.HeldItems == 1 and data.TeleporterMarker == root.CFrame)
	player.Character:PivotTo(RT.CFrame.new(12, 5, 6))
	use()
	check("テレポーターの2回目で高さを足して戻り消費する", #data.HeldItems == 0 and not data.TeleporterMarker
		and (root.Position - (origin + Vector3.new(0, Config.Items.Teleporter.HeightOffset, 0))).Magnitude == 0)
	player.Character:PivotTo(RT.CFrame.new(origin))
	use("Teleporter")
	local oldInside = ZoneManager.IsInside
	ZoneManager.IsInside = function(position) return position.X > 0 end
	local away = Vector3.new(12, 5, 6)
	player.Character:PivotTo(RT.CFrame.new(away))
	use()
	check("ゾーン縮小後はテレポーターでゾーン外に戻らず、記録だけを消す",
		data.HeldItems[1] == "Teleporter" and data.TeleporterMarker == nil and (root.Position - away).Magnitude == 0)
	ZoneManager.IsInside = oldInside
	player.Character:PivotTo(RT.CFrame.new(origin))
	use()
	local oldBounds = RT.workspace._bounds
	RT.workspace._bounds = function() return { map } end
	use()
	check("テレポーターは着地点が塞がれていたら消費しない", data.HeldItems[1] == "Teleporter"
		and data.TeleporterMarker == nil and (root.Position - origin).Magnitude == 0)
	RT.workspace._bounds = oldBounds
	use("Teleporter")
	data = GameState.ResetData(player)
	check("ラウンドのデータ初期化でテレポーターの記録が消える", data.TeleporterMarker == nil)
	GameState.Taggers[player] = nil

	player.Character:PivotTo(RT.CFrame.new(origin))
	GameState.Taggers[target] = { Since = now }
	local initialTarget = targetRoot.Position
	use("Swap")
	check("スワップは鬼も候補に含め、最も近い参加者と位置を交換する", #data.HeldItems == 0
		and root.Position.X == initialTarget.X and targetRoot.Position.X == origin.X
		and root.Position.Y == initialTarget.Y + Config.Items.Swap.HeightOffset and otherRoot.Position.X == 40)
	player.Character:PivotTo(RT.CFrame.new(origin))
	target.Character:PivotTo(RT.CFrame.new(initialTarget))
	targetHumanoid.FloorMaterial = RT.Enum.Material.Air
	use("Swap")
	check("スワップは空中の最寄り候補を飛ばして足場上の相手を選ぶ",
		#data.HeldItems == 0 and root.Position.X == 40 and (targetRoot.Position - initialTarget).Magnitude == 0)
	otherHumanoid.FloorMaterial = RT.Enum.Material.Air  -- 次の確認では交換先がない
	use("Swap")
	check("スワップは足場上の相手がいないと位置を変えず消費しない",
		data.HeldItems[1] == "Swap" and root.Position.X == 40)
	targetHumanoid.FloorMaterial, otherHumanoid.FloorMaterial = RT.Enum.Material.Concrete, RT.Enum.Material.Concrete
	player.Character:PivotTo(RT.CFrame.new(initialTarget))
	GameState.Participants[target], GameState.Participants[other] = nil, nil
	use("Swap")
	check("相手がいなければスワップを消費しない", data.HeldItems[1] == "Swap")
	GameState.Participants[target], GameState.Participants[other] = true, true

	RT.workspace._raycast = function() return nil end
	use("Grapple")
	check("着弾がなければグラップルを消費しない", data.HeldItems[1] == "Grapple")
	RT.workspace._raycast = function(position, direction)
		if direction.Y < 0 then
			return { Position = Vector3.new(position.X, position.Y - 3, position.Z - 15), Normal = Vector3.new(0, 1, 0) }
		end
	end
	use()
	check("視線の下に同じ高さの床しかなければグラップルを消費しない", data.HeldItems[1] == "Grapple")
	local aim = root.Position + Vector3.new(0, 0, -20)
	local excludesCharacters = false
	RT.workspace._raycast = function(_, direction, params)
		excludesCharacters = params.RespectCanCollide and near(direction.Magnitude, Config.Items.Grapple.Range)
			and table.find(params.FilterDescendantsInstances, player.Character)
			and table.find(params.FilterDescendantsInstances, target.Character)
		return { Position = aim, Normal = Vector3.new(0, 0, 1) }
	end
	ItemManager.TryUse(player, 1)
	check("グラップルは不発直後も使用クールダウンが効く",
		data.HeldItems[1] == "Grapple" and not data.GrapplePull and not excludesCharacters)
	use()
	local grapple = Config.Items.Grapple
	local destination = aim + Vector3.new(0, 0, grapple.SurfaceOffset)
	check("グラップルは参加者を除外して射程内に当たると引き寄せる", excludesCharacters
		and #data.HeldItems == 0 and root.AssemblyLinearVelocity.Z == -grapple.Speed)
	player.Character:PivotTo(RT.CFrame.new(destination))
	RT.game:GetService("RunService").Heartbeat:_Fire(1 / 60)
	check("グラップルは到着時に速度と引き寄せ状態を解除する", not data.GrapplePull
		and root.AssemblyLinearVelocity.Magnitude == 0 and not player.Character:GetAttribute("Grappling"))
	local top = ItemManager.GrappleDestination({ Position = aim, Normal = Vector3.new(0, 1, 0) }, 3)
	check("グラップルが上面に当たると立てる高さが移動先になる", near(top.Y, aim.Y + 3))
	player.IsBot = nil
	local restoredBeforeFreeze = false
	root.CanSetNetworkOwnership = function(self) return not self.Anchored end
	root.SetNetworkOwner = function() end
	root.SetNetworkOwnershipAuto = function(self) restoredBeforeFreeze = not self.Anchored end
	player.Character:PivotTo(RT.CFrame.new(initialTarget))
	GameState.Taggers[player] = { Since = now }
	use("Grapple")
	assert(data.GrapplePull)
	GameState.Taggers[target] = nil
	targetData.HeldItems, targetData.HeldExpireAt = { "TimeStop" }, { 0 }
	ItemManager.TryUse(target, 1)
	check("移動中の鬼を凍結すると引き寄せを解除し、固定前に自動所有権へ戻す",
		root.Anchored and restoredBeforeFreeze and not data.GrapplePull
		and not player.Character:GetAttribute("Grappling"))
	GameState.ClearFreeze(player)
	GameState.Taggers[player] = nil
	player.IsBot = true
	RT.workspace._raycast = oldRaycast

	player.Character:PivotTo(RT.CFrame.new(origin))
	target.Character:PivotTo(RT.CFrame.new(0, 3, -2))
	other.Character:PivotTo(RT.CFrame.new(40, 3, 0))
	GameState.Taggers[target] = { Since = now - Config.TagCooldown - 1 }
	use("Reflect")
	targetRoot.CFrame = RT.CFrame.new(targetRoot.Position) * RT.CFrame.Angles(0, math.pi, 0)
	data.ShieldUntil = now + 1
	RoundManager.TryTag()
	check("タッチはシールドを先に消費し、リフレクトの構えは残る", data.ShieldUntil == 0 and data.ReflectUntil > now)
	now = data.InvulnerableUntil
	RoundManager.TryTag()
	check("構え中のタッチを無効化して鬼を押し戻し、猶予を付ける", GameState.IsTagger(target)
		and data.ReflectUntil == 0 and near(data.InvulnerableUntil, now + Config.Items.Reflect.GraceTime)
		and near(targetRoot.AssemblyLinearVelocity.Z, -Config.Items.Reflect.PushSpeed))
	check("同じ構えで二度目のリフレクトは発動しない", not ItemManager.TryReflect(player, target))
	use("Reflect")
	now += Config.Items.Reflect.Duration
	ItemManager.Tick()
	check("リフレクトは未発動でも4秒で終了する", data.ReflectUntil == 0
		and not ItemManager.TryReflect(player, target))

	GameState.Taggers[target] = nil
	GameState.Taggers[other] = { Since = now }
	use("Thunder")
	check("鬼が射程外ならサンダーを消費しない", data.HeldItems[1] == "Thunder")
	GameState.Taggers[target] = { Since = now }
	ItemManager.TryUse(player, 1)
	check("サンダーは不発直後も使用クールダウンが効く", data.HeldItems[1] == "Thunder"
		and not GameState.IsStunned(target))
	use()
	check("サンダーは最寄りの鬼だけを2秒スタンさせる", #data.HeldItems == 0
		and near(targetData.StunUntil, now + Config.Items.Thunder.StunTime) and not GameState.IsStunned(other))

	use("FakeBox")
	local container = RT.workspace:FindFirstChild("SpawnedItems")
	local fake = container:FindFirstChild("ItemBox")
	check("フェイクボックスは同じ外見で本物の出現一覧に含まれない", fake
		and fake:FindFirstChild("Lid") and fake:FindFirstChild("LabelGui") and #ItemManager.GetActiveBoxPositions() == 0)
	fake.Touched:_Fire(root)
	check("フェイクボックスは設置者が触れても残る", fake.Parent == container and not GameState.IsStunned(player))
	fake:FindFirstChild("Lid").Touched:_Fire(targetRoot)
	check("フェイクボックスは相手を2秒スタンさせて消える", not fake.Parent
		and near(targetData.StunUntil, now + Config.Items.FakeBox.StunTime))

	use("FakeBox")
	fake = container:FindFirstChild("ItemBox")
	now += Config.Items.FakeBox.Duration
	ItemManager.Tick()
	check("起動しなかったフェイクボックスは20秒で消える", not fake.Parent)

	GameState.ClearStun(target)
	data.ActiveCombos.BananaFakeBox = true
	use("FakeBox")
	fake = container:FindFirstChild("ItemBox")
	fake.Touched:_Fire(targetRoot)
	check("コンボ：設置者のフェイクボックスのスタンが0.5秒延びる",
		near(targetData.StunUntil, now + Config.Items.FakeBox.StunTime + 0.5))
	GameState.ClearStun(target)

	use("Banana")
	local banana = container:FindFirstChild("BananaTrap")
	banana.Touched:_Fire(targetRoot)
	check("コンボ：設置者のバナナの転倒が0.5秒延びる",
		near(targetData.DownUntil, now + Config.Items.Banana.DownTime + 0.5))
	GameState.ClearDown(target)

	data.ActiveCombos.BananaFakeBox = nil
	targetData.ActiveCombos.BananaFakeBox = true
	use("Banana")
	banana = container:FindFirstChild("BananaTrap")
	banana.Touched:_Fire(targetRoot)
	check("コンボ：踏んだ側のコンボでは罠の効果時間は変わらない",
		near(targetData.DownUntil, now + Config.Items.Banana.DownTime))
	GameState.ClearDown(target)
	targetData.ActiveCombos.BananaFakeBox = nil

	data.ActiveCombos.HighJumpGrapple = true
	GameState.RefreshSpeed(player)
	check("コンボ：移動速度が3%上がる", near(humanoid.WalkSpeed, Config.NormalWalkSpeed * 1.03))
	data.ActiveCombos.StarDash = true
	use("Dash")
	check("コンボ：アイテムのダッシュが0.5秒延びる",
		near(data.DashUntil, now + Config.Items.Dash.Duration + 0.5))
	check("コンボ：ダッシュ中の移動速度にも3%が適用される",
		near(humanoid.WalkSpeed, Config.Items.Dash.WalkSpeed * 1.03))

	data = GameState.ResetData(player)
	GameState.RefreshSpeed(player)
	check("コンボ：ラウンドデータの初期化で発動状態と速度効果が消える",
		next(data.ActiveCombos) == nil and near(humanoid.WalkSpeed, Config.NormalWalkSpeed))

	use("IceBomb")
	local patch = container:FindFirstChild("IcePatch")
	ItemManager.Tick()
	check("氷パッチは床に置かれ範囲内の参加者に属性を付ける", patch and not patch.CanCollide
		and player.Character:GetAttribute("IcePatch") and target.Character:GetAttribute("IcePatch")
		and not other.Character:GetAttribute("IcePatch"))
	local floor = Vector3.new(0, 0, 0)
	local radius = Config.Items.IceBomb.Radius
	check("氷パッチ判定は半径の境界を含み、範囲外と高い階を除外する",
		ItemManager.IsOnIcePatch(floor, Vector3.new(radius, 0, 0))
		and not ItemManager.IsOnIcePatch(floor, Vector3.new(radius, 0, radius))
		and not ItemManager.IsOnIcePatch(floor, Vector3.new(0, Config.Items.IceBomb.HeightTolerance + 1, 0)))
	now += Config.Items.IceBomb.Duration
	ItemManager.Tick()
	check("氷パッチが消えると参加者の滑り属性も消える", not patch.Parent
		and not player.Character:GetAttribute("IcePatch") and not target.Character:GetAttribute("IcePatch"))

	local scale = RT.Instance.new("NumberValue")
	scale.Name = "BodyWidthScale"
	scale.Value = 1.2
	scale.Parent = humanoid
	use("Giant")
	check("巨大化は元のスケールを基準に体とタッチ距離を広げる",
		near(scale.Value, 1.2 * Config.Items.Giant.Scale) and near(data.GiantUntil, now + 6)
		and ItemManager.TagReachMultiplier(player, now) == Config.Items.Giant.ReachMultiplier)
	targetData.HeldItems, targetData.HeldExpireAt = { "AirBurst" }, { 0 }
	ItemManager.TryUse(target, 1)
	check("巨大化中はエアバーストの水平と上向きの勢いが弱まる",
		near(root.AssemblyLinearVelocity.Z, Config.Items.AirBurst.PushSpeed * Config.Items.Giant.KnockbackMultiplier)
		and near(root.AssemblyLinearVelocity.Y, Config.Items.AirBurst.LiftSpeed * Config.Items.Giant.KnockbackMultiplier))
	use("Shrink")
	check("縮小は巨大化と重ならず、元のスケールに倍率を掛ける", near(scale.Value, 1.2 * Config.Items.Shrink.Scale)
		and data.GiantUntil == 0 and near(data.ShrinkUntil, now + 6) and ItemManager.TagReachMultiplier(player, now) == 1)
	now += Config.Items.Shrink.Duration
	ItemManager.Tick()
	check("効果が切れると元のスケールに戻る", near(scale.Value, 1.2) and data.ShrinkUntil == 0)
	use("Giant")
	ItemManager.OnCharacterAdded(player)
	check("キャラクター再出現処理で元のスケールに戻る", near(scale.Value, 1.2) and data.GiantUntil == 0)
	use("Shrink")
	use("FakeBox")
	fake = container:FindFirstChild("ItemBox")
	use("IceBomb")
	patch = container:FindFirstChild("IcePatch")
	ItemManager.Tick()
	ItemManager.Stop()
	check("ラウンド終了で大きさが戻り、罠・パッチ・滑り属性が消える", near(scale.Value, 1.2)
		and not fake.Parent and not patch.Parent and not player.Character:GetAttribute("IcePatch"))

	ItemManager.Start()
	local bot = BotManager.Spawn(1)[1]
	local botRoot = GameState.GetRootPart(bot)
	local botData = GameState.GetData(bot)
	botData.HeldItems, botData.HeldExpireAt = { "Reflect" }, { 0 }
	target.Character:PivotTo(RT.CFrame.new(botRoot.Position + Vector3.new(2, 0, 0)))
	BotManager.Tick()
	check("ボットの通常の行動更新で近い鬼に備えてリフレクトを使う",
		#botData.HeldItems == 0 and near(botData.ReflectUntil, now + Config.Items.Reflect.Duration))
	BotManager.DespawnAll()
	ItemManager.Stop()

	for _, participant in ipairs({ player, target, other }) do
		GameState.UnregisterCharacter(participant.Character)
		GameState.ClearData(participant)
		participant.Character:Destroy()
	end
	GameState.Now, GameState.Phase = oldClock, oldPhase
	GameState.Participants, GameState.Taggers = oldParticipants, oldTaggers
	RT.workspace._raycast = oldRaycast
	if temporaryMap then temporaryMap:Destroy() end
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

	check("アイテムボックス：永続ストアなしでは購入を確定しない",
		not PlayerDataStore.AddItemBox(player) and PlayerDataStore.Get(player).ItemBoxes == 0)
	check("Studio：API 無効時もメモリ上でガチャ・装備・ルーレットを使える",
		result and equipped and spun and data.EquippedBeast == result.Id
			and data.Coins == Config.Roulette.Prizes[1].Coins and store:GetAsync("u_19007") == nil)
	PlayerDataStore.Forget(player)
end

-- すぐ遊ぶパッドの人数表示と出発時刻
do
	local createQueue = require("./.build/LobbyQueue")
	local players = {}
	local playerService = { GetPlayers = function() return players end }
	local loaded = {}
	local function addPlayer()
		local character = RT.Instance.new("Model")
		local root = RT.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Position = Vector3.new(0, 3, 0)
		root.Parent = character
		local player = RT.Instance.new("Player")
		player.Parent = playerService
		player.Character = character
		loaded[player] = true
		table.insert(players, player)
		local humanoid = RT.Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.Parent = character
		return root, humanoid, player
	end
	addPlayer()
	local root, humanoid, player = addPlayer()
	local _, dead = addPlayer()
	dead.Health = 0
	local now = 0
	local update
	local queueUpdate = { FireAllClients = function(_, value) update = value end }
	local tick, getDepartAt = createQueue(Config, playerService, loaded, point(0, 0, 0), {}, queueUpdate,
		{ clock = function() return now end })

	tick()
	local deadline = getDepartAt()
	check("参加パッド：未参加の死亡者はパッド内でも除外する", update.Count == 2)
	check("参加パッド：2人でカウントダウン開始", update.Count == 2 and update.Ready
		and deadline == Config.QuickCountdown)

	now = 1
	root.Position = Vector3.new(0, 20, 0)
	tick()
	check("参加パッド：ジャンプ中も人数と出発時刻を維持", update.Count == 2 and update.Ready
		and getDepartAt() == deadline and update.Left == Config.QuickCountdown - 1)

	local outside = Vector3.new(Config.QuickPadRadius + 1, 3, 0)
	now = 2
	root.Position = outside
	tick()
	now = 2 + Config.QuickPadExitGrace - 0.5
	tick()
	check("参加パッド：猶予中も人数を維持してカウントダウンが進む", update.Count == 2 and update.Ready
		and getDepartAt() == deadline and update.Left == math.ceil(Config.QuickCountdown - now))

	now = 2 + Config.QuickPadExitGrace
	root.Position = Vector3.new(0, 3, 0)
	tick()
	now += 0.5
	root.Position = outside
	tick()
	check("参加パッド：猶予中に戻ると次に離れたときの猶予は最初から", update.Count == 2
		and getDepartAt() == deadline)

	now += Config.QuickPadExitGrace
	tick()
	check("参加パッド：離れ続けると猶予後に外れ、カウントダウン停止", update.Count == 1
		and not update.Ready and update.Left == 0 and getDepartAt() == nil)
	root.Position = Vector3.new(0, 3, 0)
	tick()
	root.Position = outside
	tick()
	humanoid.Health = 0
	tick()
	check("参加パッド：猶予中の死亡で即座に外れる", update.Count == 1 and not update.Ready)
	humanoid.Health = 100
	root.Position = Vector3.new(0, 3, 0)
	tick()
	root.Position = outside
	tick()
	player.Parent = nil
	tick()
	check("参加パッド：猶予中の退場で即座に外れる", update.Count == 1 and not update.Ready)

end

do
	local skills = RT.modules.TaggerSkills
	local config = Config.TaggerSkills
	local readyAt = 100 + config.Dash.Cooldown
	check("鬼スキル：使用直後とクールダウン終了直前は再使用不可",
		not skills.IsReady(readyAt, 100) and not skills.IsReady(readyAt, readyAt - 0.01))
	check("鬼スキル：クールダウン終了時点から再使用可",
		skills.IsReady(readyAt, readyAt) and skills.IsReady(nil, 100))

	for _, case in ipairs({ { 90.01, 1, 0 }, { 90, 1.05, 1 }, { 30.01, 1.05, 1 }, { 30, 1.10, 2 }, { 29.99, 1.10, 2 } }) do
		local multiplier, stage = GameState.TaggerLateBoost(case[1], 180)
		check("鬼の後半強化：残り " .. case[1] .. " 秒", near(multiplier, case[2]) and stage == case[3])
	end
	local multiplier, stage = GameState.TaggerLateBoost(30, 60)
	check("鬼の後半強化：60秒戦で半分と残り30秒が重なると第2段階", near(multiplier, 1.10) and stage == 2)

	local window = config.CatchStreak.Window
	check("連続捕獲：初回の捕獲では加速しない", skills.CatchBoostEnd(nil, 100, window) == nil)
	check("連続捕獲：ちょうど10秒で3秒間加速", skills.CatchBoostEnd(100, 110, window) == 113)
	check("連続捕獲：10秒を超えると加速しない", skills.CatchBoostEnd(100, 110.01, window) == nil)

	local oldPhase, oldTime, oldMode = GameState.Phase, GameState.TimeLeft, GameState.ChosenMode
	local oldTaggers, oldParticipants, oldNow = GameState.Taggers, GameState.Participants, GameState.Now
	local now = 100
	GameState.Phase, GameState.ChosenMode = "Round", Config.SuddenDeath.NormalId
	GameState.TimeLeft = GameState.ChosenDuration
	GameState.Taggers, GameState.Participants = {}, {}
	GameState.Now = function() return now end
	local function entrant(id, x, health)
		local player = RT.Instance.new("Player")
		player.UserId = id
		player.Parent = RT.game:GetService("Players")
		local character = RT.Instance.new("Model")
		player.Character = character
		local root = RT.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Position = Vector3.new(x, 0, 0)
		root.Parent = character
		local humanoid = RT.Instance.new("Humanoid")
		humanoid.Health = health or 100
		humanoid.Parent = character
		GameState.Participants[player] = true
		return player, humanoid
	end
	local tagger, taggerHumanoid = entrant(29901, 0)
	local otherTagger = entrant(29902, 2)
	local nearby, nearbyHumanoid = entrant(29903, 12)
	local far = entrant(29904, 12.1)
	local star = entrant(29905, 4)
	local dead = entrant(29906, 6, 0)
	GameState.Taggers[tagger], GameState.Taggers[otherTagger] = { Since = 0 }, { Since = 0 }
	GameState.GetData(star).StarUntil = now + 10
	local data = GameState.GetData(tagger)
	local nearbyData = GameState.GetData(nearby)
	nearbyData.ShieldUntil, nearbyData.InvulnerableUntil, nearbyData.InsulateUntil = now + 10, now + 10, now + 10
	local targets = skills.RoarTargets(Vector3.new())
	check("咆哮：半径の境界にいる逃げ手だけを選ぶ", #targets == 1 and targets[1] == nearby)
	ItemManager.Start()
	skills.Use(tagger, "Roar")
	check("咆哮：シールド・無敵・絶縁中でも設定速度に減速し、シールドを消費しない",
		nearbyHumanoid.WalkSpeed == config.Roar.SlowSpeed and nearbyData.ShieldUntil == now + 10)
	now += config.Roar.SlowTime
	ItemManager.Tick()
	check("咆哮：既存の減速管理で効果終了時に速度を戻す", nearbyHumanoid.WalkSpeed == Config.NormalWalkSpeed)
	ItemManager.Stop()

	skills.Use(nearby, "Dash")
	check("鬼スキル：逃げ手の要求は無効", next(nearbyData.TaggerSkillReadyAt) == nil)
	data.StunUntil = now + 1
	skills.Use(tagger, "Dash")
	check("鬼スキル：スタン中の要求は無効", data.TaggerSkillReadyAt.Dash == nil)
	data.StunUntil = 0
	skills.Use(tagger, "Dash")
	local dashEnd = data.TaggerDashUntil
	now += 1
	skills.Use(tagger, "Dash")
	check("鬼ダッシュ：発動時に速度が上がり、クールダウン中は延長されない",
		taggerHumanoid.WalkSpeed == config.Dash.WalkSpeed and data.TaggerDashUntil == dashEnd)
	now = dashEnd
	skills.Tick(now)
	check("鬼ダッシュ：効果終了時に基本速度へ戻る", taggerHumanoid.WalkSpeed == Config.TaggerWalkSpeed)

	local skillRemote = Remotes.TaggerSkillUpdate
	local updates = {}
	Remotes.TaggerSkillUpdate = { FireClient = function(_, recipient, info)
		table.insert(updates, { Recipient = recipient, Smell = info.Smell })
	end }
	skills.Use(tagger, "Smell")
	check("嗅覚：発動者だけに生存中で最も近い逃げ手の情報を送る",
		#updates == 1 and updates[1].Recipient == tagger and updates[1].Smell.Distance == 4
			and near(updates[1].Smell.Position.X, 4))
	now += config.Smell.UpdateInterval
	GameState.GetRootPart(nearby).Position = Vector3.new(3, 0, 0)
	skills.Tick(now)
	check("嗅覚：0.25秒ごとに最も近い逃げ手を選び直す",
		#updates == 2 and updates[2].Recipient == tagger and updates[2].Smell.Distance == 3)
	now = data.TaggerSmellUntil
	skills.Tick(now)
	check("嗅覚：終了時に表示情報を消す", #updates == 3 and updates[3].Smell == nil)
	Remotes.TaggerSkillUpdate = skillRemote

	skills.RecordCatch(tagger, now - 2)
	skills.RecordCatch(tagger, now)
	check("連続捕獲：まだ鬼であれば加速する",
		near(taggerHumanoid.WalkSpeed, Config.TaggerWalkSpeed * config.CatchStreak.Multiplier))
	data.TaggerDashUntil = now + 2
	nearbyData.TaggerSkillReadyAt.Dash = math.huge
	nearbyData.TaggerSkillReadyAt.Smell = math.huge
	data.TaggerSkillReadyAt.Smell = nil
	Remotes.TaggerSkillUpdate = { FireClient = function(_, recipient, info)
		table.insert(updates, { Recipient = recipient, Smell = info.Smell })
	end }
	skills.Use(tagger, "Smell")
	local changed = RoundManager.SetAdminTagger(nearby)
	check("鬼交代：新しい鬼の全クールダウンをリセット", changed and next(nearbyData.TaggerSkillReadyAt) == nil)
	check("鬼交代：前の鬼にダッシュや連続捕獲が残っていても逃げ手速度に戻る",
		not GameState.IsTagger(tagger) and taggerHumanoid.WalkSpeed == Config.NormalWalkSpeed)

	check("鬼交代：前の鬼の嗅覚表示を消し、次の更新でも位置を送らない",
		updates[#updates - 1].Recipient == tagger and updates[#updates - 1].Smell == nil
		and data.TaggerDashUntil == 0 and data.TaggerSmellUntil == 0 and data.CatchBoostUntil == 0)
	local updateCount = #updates
	skills.Tick(now + config.Smell.UpdateInterval)
	check("鬼交代後の Tick では解除済みの嗅覚を再送しない", #updates == updateCount)
	Remotes.TaggerSkillUpdate = skillRemote

	for _, player in ipairs({ tagger, otherTagger, nearby, far, star, dead }) do
		TaggerLook.Clear(player)
		GameState.ClearData(player)
		player.Character:Destroy()
		player:Destroy()
	end
	GameState.Phase, GameState.TimeLeft, GameState.ChosenMode = oldPhase, oldTime, oldMode
	GameState.Taggers, GameState.Participants, GameState.Now = oldTaggers, oldParticipants, oldNow
end

do
	local GameState = RT.modules.GameState
	local BotManager = RT.modules.BotManager
	local oldPhase, oldTime = GameState.Phase, GameState.TimeLeft
	local now = GameState.Now()
	local dashSpeed = Config.Items.Dash.WalkSpeed
	local character = RT.Instance.new("Model")
	local humanoid = RT.Instance.new("Humanoid")
	humanoid.Parent = character
	local bot = { IsBot = true, Character = character }
	local data = GameState.GetData(bot)
	GameState.Phase = "Round"
	GameState.Taggers[bot] = true

	GameState.TimeLeft = Config.TaggerSkills.LateBoost.FinalSeconds
	bot.SpeedMultiplier = BotManager.StrengthForTierIndex(5) -- ダイヤ
	data.CatchBoostUntil = now + 10
	local uncappedSpeed = Config.TaggerWalkSpeed * bot.SpeedMultiplier
		* Config.TaggerSkills.LateBoost.FinalMultiplier * Config.TaggerSkills.CatchStreak.Multiplier
	GameState.RefreshSpeed(bot)
	check("鬼ボット速度上限：ダイヤの終盤最大加速と連続捕獲はダッシュ速度まで",
		uncappedSpeed > dashSpeed and near(humanoid.WalkSpeed, dashSpeed))

	GameState.TimeLeft = GameState.ChosenDuration
	bot.SpeedMultiplier = BotManager.StrengthForTierIndex(1) -- ブロンズ
	data.CatchBoostUntil = 0
	local earlySpeed = Config.TaggerWalkSpeed * bot.SpeedMultiplier
	GameState.RefreshSpeed(bot)
	check("鬼ボット速度上限：上限未満の序盤ブロンズは従来の速度",
		earlySpeed < dashSpeed and near(humanoid.WalkSpeed, earlySpeed))

	data.DashUntil = now + 10
	data.ActiveCombos.HighJumpGrapple = true
	GameState.RefreshSpeed(bot)
	check("鬼ボット速度上限：コンボを掛けた後の速度もダッシュ速度まで",
		near(humanoid.WalkSpeed, dashSpeed))

	GameState.Taggers[bot] = nil
	GameState.RefreshSpeed(bot)
	check("鬼ボット速度上限：逃げ手ボットのダッシュとコンボには適用しない",
		near(humanoid.WalkSpeed, dashSpeed * Config.ComboMultiplier(data.ActiveCombos, "SpeedMultiplier"))
		and humanoid.WalkSpeed > dashSpeed)

	local human = RT.Instance.new("Player")
	human.Character = character
	GameState.Taggers[human] = true
	GameState.GetData(human).TaggerDashUntil = now + 10
	GameState.RefreshSpeed(human)
	check("鬼ボット速度上限：人間の鬼ダッシュには適用しない",
		near(humanoid.WalkSpeed, Config.TaggerSkills.Dash.WalkSpeed) and humanoid.WalkSpeed > dashSpeed)

	GameState.Taggers[human] = nil
	GameState.ClearData(human)
	GameState.ClearData(bot)
	human:Destroy()
	character:Destroy()
	GameState.Phase, GameState.TimeLeft = oldPhase, oldTime
end

print(string.format("== 結果: 成功 %d / 失敗 %d ==", passed, failed))
if failed > 0 then
	error("テストが失敗しました")
end
