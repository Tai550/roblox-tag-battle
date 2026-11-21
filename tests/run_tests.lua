-- run_tests: v2 で追加した計算ロジックのモックテスト
-- 実行前に `python3 tests/build_tests.py` で tests/.build/ を作っておくこと。
-- 実行: luau tests/run_tests.lua

local RT = require("./.build/mockenv")

-- 依存順に本物のモジュールを読み込み、モックの参照表へ登録する
RT.modules.Config = require("./.build/Config")
RT.modules.GameState = require("./.build/GameState")
RT.modules.Remotes = require("./.build/Remotes")
RT.modules.Leaderstats = require("./.build/Leaderstats")
RT.modules.DeckManager = require("./.build/DeckManager")
RT.modules.ZoneManager = require("./.build/ZoneManager")
RT.modules.ItemManager = require("./.build/ItemManager")
RT.modules.RoundManager = require("./.build/RoundManager")

local Config = RT.modules.Config
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

print(string.format("== 結果: 成功 %d / 失敗 %d ==", passed, failed))
if failed > 0 then
	os.exit(1)
end
