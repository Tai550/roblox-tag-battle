-- MapBuilder: マップをコードで生成する（ServerScriptService.Server.MapBuilder）
--
-- MapBuilder.Build() は渋谷風の街を作る（サーバー起動時・1ラウンド目）。
-- MapBuilder.BuildPark() は広いパークを作る（2ラウンド目）。
-- MapBuilder.BuildNextRound() は呼ぶたびに渋谷 → パーク → 渋谷 … と入れ替える。
-- どちらも Workspace に次を作る。
--   Workspace.Map        … 地面・障害物・外周の透明な壁・SpawnLocation
--   Workspace.ItemSpawns … アイテムの出現ポイント。ItemManager / ZoneManager がそのまま使う
-- 既に Map / ItemSpawns があれば消してから作り直す。
--
-- 座標の決まり（上から見て）
--   渋谷は 220×220（-110〜110）。中心 (0, 0) がスクランブル交差点。
--   道路は幅36（-18〜18）で X 方向・Z 方向に1本ずつ。残りの4区画が街区（歩道を少し高くした台）。
--   パークは 340×340（-170〜170）。中心の円形広場以外は開けて、障害物は周囲に寄せる。
--   乱数は使わない。配置はすべて下の表に書いた固定値。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local MapBuilder = {}

MapBuilder.MapFolderName = "Map"
MapBuilder.CurrentMap = nil -- "Shibuya" または "Park"。Build / BuildPark / BuildNextRound が更新する

---------------------------------------------------------------------
-- 寸法
---------------------------------------------------------------------

local HALF = 110            -- 舞台の半分の幅（舞台は 220×220）
local ROAD_HALF = 18        -- 道路の半分の幅（道路幅36）
local ROAD_TOP = 0.2        -- 道路の上面の高さ
local WALK_TOP = 0.8        -- 歩道（街区の台）の上面の高さ
local TILE_TOP = 1.0        -- 広場の床タイルの上面の高さ
local WALL_HEIGHT = 30      -- 外周の透明な壁の高さ
local SPAWN_LIFT = 3        -- 出現ポイントは置く面から3スタッド上に中心を置く

MapBuilder.Half = HALF
MapBuilder.RoadHalf = ROAD_HALF

---------------------------------------------------------------------
-- 色（落ち着いた色調）
---------------------------------------------------------------------

local COLORS = {
	Base = Color3.fromRGB(72, 72, 76),        -- アスファルト（ベース）
	Road = Color3.fromRGB(48, 48, 52),        -- 濃いアスファルト（道路）
	Zebra = Color3.fromRGB(255, 255, 255),    -- 横断歩道の白（白い Part はこれだけ）
	CenterLine = Color3.fromRGB(235, 190, 40),-- 中央線（黄色）
	Sidewalk = Color3.fromRGB(186, 186, 182), -- 歩道（明るい灰色）
	PlazaTile = Color3.fromRGB(160, 120, 100),-- 広場のレンガ風タイル
	StationTile = Color3.fromRGB(150, 150, 160),
	Window = Color3.fromRGB(150, 185, 205),   -- 窓の帯
	RoofUnit = Color3.fromRGB(120, 120, 120), -- 屋上の室外機
	Ramp = Color3.fromRGB(110, 105, 95),      -- 屋上へのスロープ
	Screen = Color3.fromRGB(30, 140, 255),    -- 大型スクリーン（Neon）
	ScreenFrame = Color3.fromRGB(25, 25, 28),
	Pole = Color3.fromRGB(70, 75, 80),
	SignalHead = Color3.fromRGB(40, 40, 40),
	Lamp = Color3.fromRGB(255, 235, 180),
	PlanterBase = Color3.fromRGB(140, 135, 125),
	Hedge = Color3.fromRGB(60, 120, 60),
	VendingRed = Color3.fromRGB(200, 40, 40),
	VendingBlue = Color3.fromRGB(40, 80, 190),
	BusRoof = Color3.fromRGB(90, 110, 120),
	Bench = Color3.fromRGB(120, 85, 55),
	Barricade = Color3.fromRGB(240, 130, 30),
	Trunk = Color3.fromRGB(105, 75, 50),
	Leaves = Color3.fromRGB(70, 140, 70),
	Canopy = Color3.fromRGB(200, 200, 205),
	SpawnPad = Color3.fromRGB(170, 220, 255),
}

-- ビルの外壁色（数色をくり返し使う）
local BUILDING_COLORS = {
	Color3.fromRGB(140, 138, 130), -- 1 グレージュ
	Color3.fromRGB(95, 100, 110),  -- 2 チャコール
	Color3.fromRGB(165, 150, 130), -- 3 ベージュ
	Color3.fromRGB(120, 95, 85),   -- 4 レンガ茶
	Color3.fromRGB(110, 125, 130), -- 5 青灰
	Color3.fromRGB(175, 172, 165), -- 6 明るい灰
}

---------------------------------------------------------------------
-- 配置データ
---------------------------------------------------------------------

-- ビル（20棟）。x, z は足元の中心、w は X 方向の幅、d は Z 方向の奥行き、h は高さ、color は BUILDING_COLORS の番号。
-- ramp があるビルは屋上に登れる（ramp = スロープを付ける側と上る向き）。
--   ramp.side: "+X" / "-X" … ビルのどちらの側面にスロープを沿わせるか
--   ramp.up:   "+Z" / "-Z" … スロープがどちら向きに高くなるか（高い端が屋上と同じ高さ）
-- landmark = true のビルには大型スクリーンを付ける。
local BUILDINGS = {
	-- 北東の区画（x+, z-）：交差点の角にランドマーク
	{ name = "Landmark", x = 41, z = -41, w = 34, d = 34, h = 64, color = 2, landmark = true },
	{ name = "B02", x = 76, z = -40, w = 16, d = 32, h = 42, color = 1 },
	{ name = "B03", x = 98, z = -41, w = 16, d = 34, h = 30, color = 3 },
	{ name = "B04", x = 41, z = -86, w = 34, d = 36, h = 50, color = 5 },
	{ name = "B05", x = 87, z = -86, w = 38, d = 36, h = 36, color = 4 },
	-- 北西の区画（x-, z-）：交差点側は木のある広場
	{ name = "B06", x = -76, z = -41, w = 16, d = 34, h = 28, color = 6 },
	{ name = "B07", x = -98, z = -41, w = 16, d = 34, h = 54, color = 2 },
	{ name = "B08", x = -37, z = -86, w = 26, d = 36, h = 20, color = 3, ramp = { side = "-X", up = "-Z" } },
	{ name = "B09", x = -76, z = -86, w = 16, d = 36, h = 46, color = 1 },
	{ name = "B10", x = -98, z = -86, w = 16, d = 36, h = 30, color = 4 },
	-- 南西の区画（x-, z+）：交差点側は駅前風の広場（プレイヤーのスポーン）
	{ name = "B11", x = -87, z = 41, w = 38, d = 34, h = 34, color = 5 },
	{ name = "B12", x = -32, z = 86, w = 16, d = 36, h = 58, color = 2 },
	{ name = "B13", x = -52, z = 86, w = 12, d = 36, h = 24, color = 6 },
	{ name = "B14", x = -87, z = 86, w = 38, d = 36, h = 40, color = 3 },
	-- 南東の区画（x+, z+）：路地の多い区画。低いビル2棟は屋上に登れる
	{ name = "B15", x = 37, z = 41, w = 26, d = 34, h = 20, color = 1, ramp = { side = "+X", up = "+Z" } },
	{ name = "B16", x = 76, z = 41, w = 16, d = 34, h = 48, color = 4 },
	{ name = "B17", x = 98, z = 41, w = 16, d = 34, h = 26, color = 6 },
	{ name = "B18", x = 37, z = 86, w = 26, d = 36, h = 22, color = 5, ramp = { side = "+X", up = "+Z" } },
	{ name = "B19", x = 76, z = 86, w = 16, d = 36, h = 62, color = 2 },
	{ name = "B20", x = 98, z = 86, w = 16, d = 36, h = 38, color = 3 },
}
MapBuilder.Buildings = BUILDINGS

local RAMP_WIDTH = 6

-- 信号機（交差点の4つの角）
local SIGNALS = {
	{ x = 20, z = -20 }, { x = -20, z = -20 }, { x = -20, z = 20 }, { x = 20, z = 20 },
}

-- 街灯（道路沿いの歩道）
local STREET_LIGHTS = {}
for _, distance in ipairs({ 50, 90 }) do
	for _, sign in ipairs({ 1, -1 }) do
		-- 南北の道路沿い（道路の東西両側）
		table.insert(STREET_LIGHTS, { x = 20, z = distance * sign })
		table.insert(STREET_LIGHTS, { x = -20, z = distance * sign })
		-- 東西の道路沿い（道路の南北両側）
		table.insert(STREET_LIGHTS, { x = distance * sign, z = 20 })
		table.insert(STREET_LIGHTS, { x = distance * sign, z = -20 })
	end
end

-- 植え込み（along = 長い向き "X" / "Z"）
local PLANTERS = {
	{ x = 20, z = -35, along = "Z" }, { x = -20, z = -35, along = "Z" },
	{ x = 20, z = 35, along = "Z" }, { x = -20, z = 35, along = "Z" },
	{ x = 35, z = -20, along = "X" }, { x = -35, z = -20, along = "X" },
	{ x = 35, z = 20, along = "X" }, { x = -35, z = 20, along = "X" },
}

-- 自販機風の箱（路地に置く）
local VENDING_MACHINES = {
	{ x = 60.5, z = -30, color = "VendingRed" },
	{ x = 60.5, z = -34, color = "VendingBlue" },
	{ x = 66, z = 30, color = "VendingRed" },
	{ x = -62, z = 30, color = "VendingBlue" },
	{ x = -62, z = -80, color = "VendingRed" },
	{ x = -62, z = -84, color = "VendingBlue" },
}

-- バス停（屋根・柱2本・ベンチ）。along は屋根の長い向き、postSide は柱を立てる側（建物側）
local BUS_STOPS = {
	{ x = -23, z = 46, along = "Z" }, -- 駅前広場の道路側
	{ x = 76, z = 21, along = "X" },  -- 南東区画の歩道
}

-- バリケード（道路の上の障害物）。along は長い向き
local BARRICADES = {
	{ x = -8, z = 60, along = "X" }, { x = 8, z = -60, along = "X" },
	{ x = 60, z = 8, along = "Z" }, { x = -60, z = -8, along = "Z" },
	{ x = -8, z = -95, along = "X" }, { x = 8, z = 95, along = "X" },
}

-- 広場（床タイル）。x, z は中心、size は一辺
local PLAZAS = {
	{ name = "TreePlaza", x = -41, z = -41, size = 38, color = "PlazaTile" },
	{ name = "StationPlaza", x = -41, z = 41, size = 38, color = "StationTile" },
}

-- 木（幹＝円柱、葉＝球）。広場のタイルの上に立てる
local TREES = {
	{ x = -30, z = -30 }, { x = -52, z = -30 }, { x = -30, z = -52 }, { x = -52, z = -52 },
	{ x = -56, z = 30 }, { x = -28, z = 56 },
}

-- ベンチ（木の広場）
local BENCHES = {
	{ x = -41, z = -30 }, { x = -41, z = -52 },
}

-- 駅の入口風の屋根（駅前広場の奥）
local STATION_CANOPY = { x = -48, z = 56, w = 16, d = 8, height = 8 }

-- プレイヤーのスポーン（駅前広場、交差点の近く）
local PLAYER_SPAWN = { x = -34, z = 34, size = 12 }

-- アイテムの出現ポイント（12点）。surface = 置く面の高さ（中心はその3スタッド上）
-- roof = ビル名 のときはそのビルの屋上に置く
local ITEM_SPAWNS = {
	{ x = 0, z = 0, surface = ROAD_TOP },        -- 1 スクランブル交差点の中央
	{ x = 30, z = -21, surface = WALK_TOP },     -- 2 ランドマーク前の歩道
	{ x = 63, z = -45, surface = WALK_TOP },     -- 3 北東の路地（自販機の奥）
	{ x = 87, z = -41, surface = WALK_TOP },     -- 4 北東の細い路地
	{ x = -41, z = -41, surface = TILE_TOP },    -- 5 木のある広場
	{ x = -37, z = -86, roof = "B08" },          -- 6 屋上（北西の低いビル）
	{ x = 37, z = 41, roof = "B15" },            -- 7 屋上（南東の低いビル）
	{ x = -48, z = 50, surface = TILE_TOP },     -- 8 駅前広場（駅の入口の前）
	{ x = 87, z = 41, surface = WALK_TOP },      -- 9 南東の細い路地
	{ x = -43, z = 86, surface = WALK_TOP },     -- 10 南西の細い路地
	{ x = 62, z = 64, surface = WALK_TOP },      -- 11 南東の裏路地（路地の交差点）
	{ x = -64, z = 64, surface = WALK_TOP },     -- 12 南西の裏路地
}
MapBuilder.ItemSpawnCount = #ITEM_SPAWNS

---------------------------------------------------------------------
-- パーク（340×340。広くて見通しがよい。障害物は周囲に寄せる）
---------------------------------------------------------------------

local PARK_HALF = 170
local PARK_GRASS_TOP = 0
local PARK_PLAZA_TOP = 0.5 -- 中央の円形広場の上面
local PARK_WALL_HEIGHT = 36

MapBuilder.ParkHalf = PARK_HALF

local PARK = {
	Grass = Color3.fromRGB(86, 148, 72),
	GrassDark = Color3.fromRGB(68, 122, 58),
	Path = Color3.fromRGB(186, 168, 132),
	Plaza = Color3.fromRGB(168, 164, 156),
	Water = Color3.fromRGB(64, 140, 186),
	Bank = Color3.fromRGB(78, 124, 78),
	Lily = Color3.fromRGB(72, 156, 86),
	Mound = Color3.fromRGB(108, 142, 76),
	Rock = Color3.fromRGB(132, 130, 124),
	Trunk = Color3.fromRGB(112, 80, 50),
	Leaves = Color3.fromRGB(58, 136, 66),
	Bench = Color3.fromRGB(132, 92, 58),
	Fence = Color3.fromRGB(168, 166, 158),
	Wood = Color3.fromRGB(148, 112, 74),
	Roof = Color3.fromRGB(122, 74, 58),
	Door = Color3.fromRGB(92, 64, 44),
	Pillar = Color3.fromRGB(186, 160, 120),
	FlowerRed = Color3.fromRGB(214, 96, 112),
	FlowerYellow = Color3.fromRGB(230, 196, 72),
	Lamp = Color3.fromRGB(255, 236, 190),
	Pole = Color3.fromRGB(96, 100, 104),
	SpawnPad = Color3.fromRGB(176, 214, 170),
}

-- 出現ポイント（14点、屋外のみ）。surface は置く面の高さ（中心はその3スタッド上）
local PARK_SPAWNS = {
	{ x = 14, z = 10, surface = PARK_PLAZA_TOP },    -- 1 中央広場
	{ x = -16, z = 18, surface = PARK_PLAZA_TOP },   -- 2 中央広場
	{ x = 20, z = -12, surface = PARK_PLAZA_TOP },   -- 3 中央広場
	{ x = 58, z = 22, surface = PARK_GRASS_TOP },    -- 4 東の芝生
	{ x = -62, z = 28, surface = PARK_GRASS_TOP },   -- 5 西の芝生
	{ x = 36, z = 62, surface = PARK_GRASS_TOP },    -- 6 北の芝生
	{ x = -40, z = -48, surface = PARK_GRASS_TOP },  -- 7 南の芝生（池の手前）
	{ x = 100, z = -30, surface = PARK_GRASS_TOP },  -- 8 東、あずまやの北
	{ x = -130, z = 125, surface = PARK_GRASS_TOP }, -- 9 北西の木立の向こう
	{ x = 150, z = 95, surface = PARK_GRASS_TOP },   -- 10 北東の外れ
	{ x = -158, z = -125, surface = PARK_GRASS_TOP },-- 11 南西の隅
	{ x = 78, z = 150, surface = PARK_GRASS_TOP },   -- 12 北の外れ
	{ x = 155, z = -155, surface = PARK_GRASS_TOP }, -- 13 南東の隅
	{ x = -95, z = 150, surface = PARK_GRASS_TOP },  -- 14 北の外れ（西寄り）
}
MapBuilder.ParkSpawnCount = #PARK_SPAWNS

-- 中央から放射する散歩道（軸上。長さ40、内端は広場のふち）
local PARK_PATHS = {
	{ x = 0, z = -54, sx = 8, sz = 40 },
	{ x = 0, z = 54, sx = 8, sz = 40 },
	{ x = 54, z = 0, sx = 40, sz = 8 },
	{ x = -54, z = 0, sx = 40, sz = 8 },
}

-- 池（歩けはする。泳げない。青い面）
local PARK_POND = { x = -105, z = -65, w = 40, d = 26 }

-- 低い丘（半分地面に埋めた球）
local PARK_MOUNDS = {
	{ x = 105, z = 105, sx = 22, sy = 7, sz = 18 },
	{ x = -115, z = 115, sx = 20, sy = 6, sz = 16 },
	{ x = 145, z = -115, sx = 22, sy = 6, sz = 18 },
	{ x = -155, z = -45, sx = 16, sy = 5, sz = 14 },
	{ x = 45, z = -115, sx = 18, sy = 5, sz = 16 },
}

local PARK_ROCKS = {
	{ x = 90, z = 85, sx = 4.5, sy = 3.2, sz = 4 },
	{ x = 140, z = -90, sx = 5, sy = 3.4, sz = 4.2 },
	{ x = -90, z = 100, sx = 3.8, sy = 2.8, sz = 3.6 },
	{ x = -150, z = -70, sx = 4.2, sy = 3, sz = 3.8 },
	{ x = 55, z = 85, sx = 3.4, sy = 2.4, sz = 3.2 },
	{ x = -35, z = 78, sx = 3.6, sy = 2.6, sz = 3.4 },
}

-- 木の群れ（中心の見通しは空け、四隅に寄せる）
local PARK_TREES = {
	{ x = -118, z = 72 }, { x = -132, z = 78 }, { x = -122, z = 90 }, { x = -136, z = 64 },
	{ x = 112, z = 118 }, { x = 128, z = 124 }, { x = 118, z = 136 },
	{ x = -108, z = -112 }, { x = -122, z = -124 }, { x = -112, z = -134 },
	{ x = 108, z = -125 }, { x = 122, z = -138 },
}

local PARK_BENCHES = {
	{ x = 34, z = 34 }, { x = -34, z = 34 }, { x = 34, z = -34 }, { x = -34, z = -34 },
	{ x = -78, z = -48 }, { x = 52, z = -58 },
}

-- 低いフェンス（along は長い向き）。中央の直線は塞がない
local PARK_FENCES = {
	{ x = -128, z = 100, along = "X", length = 22 },
	{ x = 120, z = 148, along = "X", length = 20 },
	{ x = -115, z = -148, along = "X", length = 18 },
	{ x = 150, z = -120, along = "Z", length = 16 },
	{ x = -160, z = 40, along = "Z", length = 18 },
	{ x = 96, z = 158, along = "X", length = 16 },
}

-- あずまや（屋根と柱）。南東寄りの芝生
local PARK_GAZEBO = { x = 72, z = -78, floor = 14, height = 7.5 }

-- 低めの小屋（登れない。高さは 8〜10）
local PARK_HUTS = {
	{ x = 125, z = 45, w = 16, d = 12, h = 9 },
	{ x = -145, z = 20, w = 14, d = 12, h = 8 },
	{ x = 25, z = 140, w = 16, d = 14, h = 10 },
	{ x = -55, z = -148, w = 18, d = 14, h = 9 },
}

local PARK_FLOWERS = {
	{ x = 48, z = 48, color = "FlowerRed" },
	{ x = -48, z = 48, color = "FlowerYellow" },
	{ x = 48, z = -48, color = "FlowerYellow" },
	{ x = -48, z = -48, color = "FlowerRed" },
	{ x = 10, z = 70, color = "FlowerRed" },
	{ x = -70, z = 10, color = "FlowerYellow" },
}

-- 広場の外側、道の軸からはずらす
local PARK_LAMPS = {
	{ x = 40, z = -22 }, { x = -22, z = -40 }, { x = 22, z = 40 }, { x = -40, z = 22 },
}

local PARK_PLAYER_SPAWN = { x = 0, z = 0, size = 12 }

---------------------------------------------------------------------
-- 部品を作る小さな道具
---------------------------------------------------------------------

local partCount = 0

-- props: Size = {x,y,z}, Pos = {x,y,z}, Color, Material, Name, ClassName, Shape,
--        Transparency, CanCollide, RotY / RotZ（度）
local function makePart(parent, props)
	local part = Instance.new(props.ClassName or "Part")
	part.Name = props.Name or "Part"
	part.Anchored = true
	part.CanCollide = props.CanCollide ~= false
	part.Size = Vector3.new(props.Size[1], props.Size[2], props.Size[3])
	part.Position = Vector3.new(props.Pos[1], props.Pos[2], props.Pos[3])
	if props.RotY or props.RotZ then
		part.CFrame = CFrame.new(props.Pos[1], props.Pos[2], props.Pos[3])
			* CFrame.Angles(0, math.rad(props.RotY or 0), math.rad(props.RotZ or 0))
	end
	if props.Shape then
		part.Shape = props.Shape
	end
	part.Color = props.Color or COLORS.Base
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	partCount = partCount + 1
	return part
end

local function makeFolder(parent, name)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- 縦に立てた円柱（Roblox の円柱は X 軸方向が長さなので Z 軸で90度回す）
local function makeColumn(parent, name, x, bottomY, z, height, diameter, color, material)
	return makePart(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = { height, diameter, diameter },
		Pos = { x, bottomY + height / 2, z },
		RotZ = 90,
		Color = color,
		Material = material,
	})
end

-- along が "X" なら (長さ, 短さ) を X/Z に、"Z" なら入れ替える
local function alongSize(along, long, short)
	if along == "X" then
		return long, short
	end
	return short, long
end

---------------------------------------------------------------------
-- 地面・道路・横断歩道・歩道・外周
---------------------------------------------------------------------

local function buildGround(map)
	local folder = makeFolder(map, "Ground")

	-- 地面のベース（大きな1枚）
	makePart(folder, {
		Name = "Base",
		Size = { HALF * 2, 2, HALF * 2 },
		Pos = { 0, -1, 0 },
		Color = COLORS.Base,
		Material = Enum.Material.Asphalt,
	})

	-- 道路：南北に1本（全長）、東西は交差点の東と西に分けて重なりを避ける
	local roadLen = HALF - ROAD_HALF
	makePart(folder, {
		Name = "RoadNS",
		Size = { ROAD_HALF * 2, ROAD_TOP, HALF * 2 },
		Pos = { 0, ROAD_TOP / 2, 0 },
		Color = COLORS.Road,
		Material = Enum.Material.Asphalt,
	})
	for _, sign in ipairs({ 1, -1 }) do
		makePart(folder, {
			Name = "RoadEW",
			Size = { roadLen, ROAD_TOP, ROAD_HALF * 2 },
			Pos = { sign * (ROAD_HALF + roadLen / 2), ROAD_TOP / 2, 0 },
			Color = COLORS.Road,
			Material = Enum.Material.Asphalt,
		})
	end

	-- 中央線：交差点と横断歩道の外側から舞台の端まで、4方向に1本ずつ
	local lineStart = 30
	local lineLen = HALF - lineStart
	local lineMid = lineStart + lineLen / 2
	for _, sign in ipairs({ 1, -1 }) do
		makePart(folder, {
			Name = "CenterLine",
			Size = { 0.6, 0.05, lineLen },
			Pos = { 0, ROAD_TOP + 0.025, sign * lineMid },
			Color = COLORS.CenterLine,
		})
		makePart(folder, {
			Name = "CenterLine",
			Size = { lineLen, 0.05, 0.6 },
			Pos = { sign * lineMid, ROAD_TOP + 0.025, 0 },
			Color = COLORS.CenterLine,
		})
	end

	-- 歩道：4つの街区それぞれを少し高い台にする（区画の周囲がそのまま歩道になる）
	local blockSize = HALF - ROAD_HALF
	local blockMid = ROAD_HALF + blockSize / 2
	for _, sx in ipairs({ 1, -1 }) do
		for _, sz in ipairs({ 1, -1 }) do
			makePart(folder, {
				Name = "Sidewalk",
				Size = { blockSize, WALK_TOP, blockSize },
				Pos = { sx * blockMid, WALK_TOP / 2, sz * blockMid },
				Color = COLORS.Sidewalk,
				Material = Enum.Material.Concrete,
			})
		end
	end

	-- 広場の床タイル
	for _, plaza in ipairs(PLAZAS) do
		makePart(folder, {
			Name = plaza.name,
			Size = { plaza.size, TILE_TOP - WALK_TOP, plaza.size },
			Pos = { plaza.x, (WALK_TOP + TILE_TOP) / 2, plaza.z },
			Color = COLORS[plaza.color],
			Material = Enum.Material.Brick,
		})
	end
end

-- 横断歩道：交差点の4方向すべてに白い帯（ゼブラ模様）
local CROSSWALK_INNER = ROAD_HALF + 1  -- 交差点側の端
local CROSSWALK_DEPTH = 8              -- 横断歩道の奥行き（帯の長さ）
local STRIPE_WIDTH = 2
local STRIPE_PITCH = 4

local function buildCrosswalks(map)
	local folder = makeFolder(map, "Crosswalks")
	local mid = CROSSWALK_INNER + CROSSWALK_DEPTH / 2
	local y = ROAD_TOP + 0.025
	for offset = -(ROAD_HALF - 2), ROAD_HALF - 2, STRIPE_PITCH do
		for _, sign in ipairs({ 1, -1 }) do
			-- 南北の道路を渡る横断歩道（交差点の北と南）
			makePart(folder, {
				Name = "Zebra",
				Size = { STRIPE_WIDTH, 0.05, CROSSWALK_DEPTH },
				Pos = { offset, y, sign * mid },
				Color = COLORS.Zebra,
			})
			-- 東西の道路を渡る横断歩道（交差点の東と西）
			makePart(folder, {
				Name = "Zebra",
				Size = { CROSSWALK_DEPTH, 0.05, STRIPE_WIDTH },
				Pos = { sign * mid, y, offset },
				Color = COLORS.Zebra,
			})
		end
	end
end

-- 外周の透明な壁（舞台の外に出られないようにする）
local function buildBoundary(map)
	local folder = makeFolder(map, "Boundary")
	local thickness = 2
	local offset = HALF + thickness / 2
	local length = HALF * 2 + thickness * 2
	for _, sign in ipairs({ 1, -1 }) do
		makePart(folder, {
			Name = "InvisibleWall",
			Size = { thickness, WALL_HEIGHT, length },
			Pos = { sign * offset, WALL_HEIGHT / 2, 0 },
			Transparency = 1,
		})
		makePart(folder, {
			Name = "InvisibleWall",
			Size = { length, WALL_HEIGHT, thickness },
			Pos = { 0, WALL_HEIGHT / 2, sign * offset },
			Transparency = 1,
		})
	end
end

---------------------------------------------------------------------
-- ビル
---------------------------------------------------------------------

-- 窓の帯の本数（下から6スタッド目を起点に10スタッドおき。屋上の2スタッド手前まで）
local function windowBandCount(height)
	return math.floor((height - 9.5) / 10) + 1
end
MapBuilder.WindowBandCount = windowBandCount

-- スロープの位置と向きを計算する（テストからも呼べるように公開）
-- 戻り値: 中心 x, 中心 z, 幅（X）, 長さ（Z）, Y 回転（度）
function MapBuilder.RampGeometry(building)
	local ramp = building.ramp
	local sideSign = (ramp.side == "+X") and 1 or -1
	local cx = building.x + sideSign * (building.w / 2 + RAMP_WIDTH / 2)
	-- WedgePart は +Z 側が高い。-Z 側を高くしたいときは Y 軸で180度回す
	local rotY = (ramp.up == "+Z") and 0 or 180
	return cx, building.z, RAMP_WIDTH, building.d, rotY
end

local function buildBuildings(map)
	local folder = makeFolder(map, "Buildings")
	local climbable = 0
	for _, b in ipairs(BUILDINGS) do
		local model = Instance.new("Model")
		model.Name = b.name
		local roofY = WALK_TOP + b.h

		-- 本体（箱）
		makePart(model, {
			Name = "Body",
			Size = { b.w, b.h, b.d },
			Pos = { b.x, WALK_TOP + b.h / 2, b.z },
			Color = BUILDING_COLORS[b.color],
			Material = Enum.Material.Concrete,
		})

		-- 窓の帯：本体より少しだけ大きい薄い板を巻き付け、4面すべてに帯を出す（1本＝1 Part）
		for index = 1, windowBandCount(b.h) do
			makePart(model, {
				Name = "WindowBand",
				Size = { b.w + 0.4, 3, b.d + 0.4 },
				Pos = { b.x, WALK_TOP + 6 + (index - 1) * 10, b.z },
				Color = COLORS.Window,
				Material = Enum.Material.Glass,
			})
		end

		-- 屋上の室外機（屋上の隠れ場所にもなる）
		makePart(model, {
			Name = "RoofUnit",
			Size = { 4, 2, 4 },
			Pos = { b.x + b.w / 4, roofY + 1, b.z + b.d / 4 },
			Color = COLORS.RoofUnit,
			Material = Enum.Material.Metal,
		})

		-- 屋上へのスロープ：側面にぴったり沿わせ、高い端が屋上と同じ高さになる
		if b.ramp then
			local cx, cz, width, length, rotY = MapBuilder.RampGeometry(b)
			makePart(model, {
				Name = "RoofRamp",
				ClassName = "WedgePart",
				Size = { width, b.h, length },
				Pos = { cx, WALK_TOP + b.h / 2, cz },
				RotY = rotY,
				Color = COLORS.Ramp,
				Material = Enum.Material.Concrete,
			})
			climbable = climbable + 1
		end

		-- ランドマーク：交差点側（+Z 面）に Neon の大型スクリーンと「SHIBUYA」の表示
		if b.landmark then
			local faceZ = b.z + b.d / 2 + 0.2 -- 窓の帯の表面
			local screenY = WALK_TOP + b.h - 20
			makePart(model, {
				Name = "ScreenFrame",
				Size = { 28, 18, 0.4 },
				Pos = { b.x, screenY, faceZ + 0.2 },
				Color = COLORS.ScreenFrame,
			})
			local screen = makePart(model, {
				Name = "Screen",
				Size = { 26, 16, 0.8 },
				Pos = { b.x, screenY, faceZ + 0.4 + 0.4 },
				Color = COLORS.Screen,
				Material = Enum.Material.Neon,
			})
			local gui = Instance.new("SurfaceGui")
			gui.Name = "ScreenGui"
			gui.Face = Enum.NormalId.Back -- +Z 面（交差点側）
			gui.LightInfluence = 0
			gui.PixelsPerStud = 20
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			local label = Instance.new("TextLabel")
			label.Name = "Title"
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = "SHIBUYA"
			label.TextScaled = true
			label.Font = Enum.Font.GothamBlack
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.Parent = gui
			gui.Parent = screen
		end

		model.Parent = folder
	end
	return climbable
end

---------------------------------------------------------------------
-- 小物（障害物・隠れ場所）
---------------------------------------------------------------------

local function buildProps(map)
	local folder = makeFolder(map, "Props")

	-- 信号機：柱＋灯器
	for _, s in ipairs(SIGNALS) do
		makeColumn(folder, "SignalPole", s.x, WALK_TOP, s.z, 12, 0.8, COLORS.Pole)
		makePart(folder, {
			Name = "SignalHead",
			Size = { 1.2, 3, 1.2 },
			Pos = { s.x, WALK_TOP + 11.5, s.z },
			Color = COLORS.SignalHead,
		})
	end

	-- 街灯：柱＋光る笠
	for _, l in ipairs(STREET_LIGHTS) do
		makeColumn(folder, "LightPole", l.x, WALK_TOP, l.z, 14, 0.6, COLORS.Pole)
		makePart(folder, {
			Name = "Lamp",
			Size = { 1.6, 0.6, 1.6 },
			Pos = { l.x, WALK_TOP + 14.3, l.z },
			Color = COLORS.Lamp,
			Material = Enum.Material.Neon,
		})
	end

	-- 植え込み：台＋生け垣
	for _, p in ipairs(PLANTERS) do
		local sx, sz = alongSize(p.along, 6, 2)
		makePart(folder, {
			Name = "Planter",
			Size = { sx, 1.5, sz },
			Pos = { p.x, WALK_TOP + 0.75, p.z },
			Color = COLORS.PlanterBase,
			Material = Enum.Material.Concrete,
		})
		makePart(folder, {
			Name = "Hedge",
			Size = { sx - 0.2, 1.5, sz - 0.2 },
			Pos = { p.x, WALK_TOP + 2.25, p.z },
			Color = COLORS.Hedge,
			Material = Enum.Material.Grass,
		})
	end

	-- 自販機風の箱
	for _, v in ipairs(VENDING_MACHINES) do
		makePart(folder, {
			Name = "VendingMachine",
			Size = { 3, 6, 2 },
			Pos = { v.x, WALK_TOP + 3, v.z },
			Color = COLORS[v.color],
		})
	end

	-- バス停：屋根・柱2本・ベンチ
	for _, stop in ipairs(BUS_STOPS) do
		local roofX, roofZ = alongSize(stop.along, 10, 4)
		makePart(folder, {
			Name = "BusStopRoof",
			Size = { roofX, 0.5, roofZ },
			Pos = { stop.x, WALK_TOP + 7.25, stop.z },
			Color = COLORS.BusRoof,
			Material = Enum.Material.Metal,
		})
		for _, k in ipairs({ -1, 1 }) do
			-- 柱は屋根の長い向きの両端、建物側（道路から遠い側）に立てる
			local px, pz
			if stop.along == "Z" then
				px, pz = stop.x - 1.5, stop.z + k * 4
			else
				px, pz = stop.x + k * 4, stop.z + 1.5
			end
			makePart(folder, {
				Name = "BusStopPost",
				Size = { 0.5, 7, 0.5 },
				Pos = { px, WALK_TOP + 3.5, pz },
				Color = COLORS.Pole,
			})
		end
		local benchX, benchZ = alongSize(stop.along, 6, 1.5)
		local bx, bz = stop.x, stop.z
		if stop.along == "Z" then
			bx = stop.x - 0.8
		else
			bz = stop.z + 0.8
		end
		makePart(folder, {
			Name = "BusStopBench",
			Size = { benchX, 1, benchZ },
			Pos = { bx, WALK_TOP + 1, bz },
			Color = COLORS.Bench,
			Material = Enum.Material.Wood,
		})
	end

	-- バリケード（道路の上）
	for _, br in ipairs(BARRICADES) do
		local sx, sz = alongSize(br.along, 8, 1)
		makePart(folder, {
			Name = "Barricade",
			Size = { sx, 3, sz },
			Pos = { br.x, ROAD_TOP + 1.5, br.z },
			Color = COLORS.Barricade,
		})
	end

	-- 木：幹（円柱）＋葉（球）
	for _, t in ipairs(TREES) do
		makeColumn(folder, "TreeTrunk", t.x, TILE_TOP, t.z, 6, 1.2, COLORS.Trunk)
		makePart(folder, {
			Name = "TreeLeaves",
			Shape = Enum.PartType.Ball,
			Size = { 7, 7, 7 },
			Pos = { t.x, TILE_TOP + 8, t.z },
			Color = COLORS.Leaves,
			Material = Enum.Material.Grass,
		})
	end

	-- 広場のベンチ
	for _, bench in ipairs(BENCHES) do
		makePart(folder, {
			Name = "Bench",
			Size = { 6, 1, 1.5 },
			Pos = { bench.x, TILE_TOP + 0.5, bench.z },
			Color = COLORS.Bench,
			Material = Enum.Material.Wood,
		})
	end

	-- 駅の入口風の屋根（柱2本）
	local c = STATION_CANOPY
	makePart(folder, {
		Name = "StationCanopy",
		Size = { c.w, 1, c.d },
		Pos = { c.x, TILE_TOP + c.height + 0.5, c.z },
		Color = COLORS.Canopy,
		Material = Enum.Material.Metal,
	})
	for _, k in ipairs({ -1, 1 }) do
		makePart(folder, {
			Name = "StationPillar",
			Size = { 1, c.height, 1 },
			Pos = { c.x + k * (c.w / 2 - 1), TILE_TOP + c.height / 2, c.z },
			Color = COLORS.Pole,
		})
	end
end

-- プレイヤーのスポーン（駅前広場）
local function buildPlayerSpawn(map)
	local spawn = makePart(map, {
		Name = "PlayerSpawn",
		ClassName = "SpawnLocation",
		Size = { PLAYER_SPAWN.size, 1, PLAYER_SPAWN.size },
		Pos = { PLAYER_SPAWN.x, TILE_TOP + 0.5, PLAYER_SPAWN.z },
		Color = COLORS.SpawnPad,
		Transparency = 0.3,
	})
	spawn.Neutral = true
	return spawn
end

---------------------------------------------------------------------
-- 出現ポイント
---------------------------------------------------------------------

local function findBuilding(name)
	for _, b in ipairs(BUILDINGS) do
		if b.name == name then
			return b
		end
	end
	return nil
end

-- 出現ポイントの中心座標の一覧を返す（テストからも呼べる）
function MapBuilder.ItemSpawnPositions()
	local list = {}
	for _, s in ipairs(ITEM_SPAWNS) do
		local surface = s.surface
		if s.roof then
			local b = findBuilding(s.roof)
			surface = WALK_TOP + b.h
		end
		table.insert(list, { x = s.x, y = surface + SPAWN_LIFT, z = s.z, roof = s.roof })
	end
	return list
end

-- パークの出現ポイント（テストからも呼べる）
function MapBuilder.ParkSpawnPositions()
	local list = {}
	for _, s in ipairs(PARK_SPAWNS) do
		table.insert(list, { x = s.x, y = s.surface + SPAWN_LIFT, z = s.z })
	end
	return list
end

local function buildItemSpawns(positions)
	local folder = Instance.new("Folder")
	folder.Name = Config.ItemSpawnFolderName
	for index, p in ipairs(positions) do
		makePart(folder, {
			Name = "Spawn" .. index,
			Size = { 2, 1, 2 },
			Pos = { p.x, p.y, p.z },
			Transparency = 1,
			CanCollide = false,
		})
	end
	return folder
end

local function clearExistingMap()
	local oldMap = workspace:FindFirstChild(MapBuilder.MapFolderName)
	if oldMap then
		oldMap:Destroy()
	end
	local oldSpawns = workspace:FindFirstChild(Config.ItemSpawnFolderName)
	if oldSpawns then
		oldSpawns:Destroy()
	end
	partCount = 0
end

---------------------------------------------------------------------
-- パークの生成
---------------------------------------------------------------------

local function buildParkGround(map)
	local folder = makeFolder(map, "Ground")
	makePart(folder, {
		Name = "Grass",
		Size = { PARK_HALF * 2, 2, PARK_HALF * 2 },
		Pos = { 0, -1, 0 },
		Color = PARK.Grass,
		Material = Enum.Material.Grass,
	})
	-- 円形の舗装（円柱を寝かせて薄い円盤にする）
	makeColumn(folder, "Plaza", 0, PARK_GRASS_TOP, 0, PARK_PLAZA_TOP, 72, PARK.Plaza, Enum.Material.Concrete)
	for _, path in ipairs(PARK_PATHS) do
		makePart(folder, {
			Name = "Path",
			Size = { path.sx, 0.3, path.sz },
			Pos = { path.x, 0.15, path.z },
			Color = PARK.Path,
			Material = Enum.Material.Concrete,
		})
	end
end

local function buildParkBoundary(map)
	local folder = makeFolder(map, "Boundary")
	local thickness = 2
	local offset = PARK_HALF + thickness / 2
	local length = PARK_HALF * 2 + thickness * 2
	for _, sign in ipairs({ 1, -1 }) do
		makePart(folder, {
			Name = "InvisibleWall",
			Size = { thickness, PARK_WALL_HEIGHT, length },
			Pos = { sign * offset, PARK_WALL_HEIGHT / 2, 0 },
			Transparency = 1,
		})
		makePart(folder, {
			Name = "InvisibleWall",
			Size = { length, PARK_WALL_HEIGHT, thickness },
			Pos = { 0, PARK_WALL_HEIGHT / 2, sign * offset },
			Transparency = 1,
		})
	end
end

local function buildParkProps(map)
	local folder = makeFolder(map, "Props")
	local pond = PARK_POND

	makePart(folder, {
		Name = "PondBank",
		Size = { pond.w + 6, 0.3, pond.d + 6 },
		Pos = { pond.x, 0.15, pond.z },
		Color = PARK.Bank,
		Material = Enum.Material.Grass,
	})
	makePart(folder, {
		Name = "Pond",
		Size = { pond.w, 0.25, pond.d },
		Pos = { pond.x, 0.28, pond.z },
		Color = PARK.Water,
		Material = Enum.Material.Water,
		Transparency = 0.15,
	})
	for _, lily in ipairs({ { x = -8, z = -4 }, { x = 6, z = 5 }, { x = -2, z = 8 } }) do
		makePart(folder, {
			Name = "Lily",
			Size = { 3.2, 0.12, 3.2 },
			Pos = { pond.x + lily.x, 0.42, pond.z + lily.z },
			Color = PARK.Lily,
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end

	for _, mound in ipairs(PARK_MOUNDS) do
		makePart(folder, {
			Name = "Mound",
			Shape = Enum.PartType.Ball,
			Size = { mound.sx, mound.sy, mound.sz },
			Pos = { mound.x, mound.sy / 2 - 1.5, mound.z },
			Color = PARK.Mound,
			Material = Enum.Material.Grass,
		})
	end

	for _, rock in ipairs(PARK_ROCKS) do
		makePart(folder, {
			Name = "Rock",
			Shape = Enum.PartType.Ball,
			Size = { rock.sx, rock.sy, rock.sz },
			Pos = { rock.x, rock.sy / 2 - 0.4, rock.z },
			Color = PARK.Rock,
			Material = Enum.Material.Slate,
		})
	end

	for _, tree in ipairs(PARK_TREES) do
		makeColumn(folder, "TreeTrunk", tree.x, PARK_GRASS_TOP, tree.z, 7, 1.3, PARK.Trunk, Enum.Material.Wood)
		makePart(folder, {
			Name = "TreeLeaves",
			Shape = Enum.PartType.Ball,
			Size = { 7.5, 7.5, 7.5 },
			Pos = { tree.x, 10.2, tree.z },
			Color = PARK.Leaves,
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end

	for _, bench in ipairs(PARK_BENCHES) do
		makePart(folder, {
			Name = "Bench",
			Size = { 5, 0.4, 1.6 },
			Pos = { bench.x, 1.2, bench.z },
			Color = PARK.Bench,
			Material = Enum.Material.Wood,
		})
		makePart(folder, {
			Name = "BenchBack",
			Size = { 5, 1.2, 0.3 },
			Pos = { bench.x, 2.0, bench.z + 0.7 },
			Color = PARK.Bench,
			Material = Enum.Material.Wood,
		})
	end

	for _, fence in ipairs(PARK_FENCES) do
		local sx, sz = alongSize(fence.along, fence.length, 0.4)
		makePart(folder, {
			Name = "FenceRail",
			Size = { sx, 2, sz },
			Pos = { fence.x, 1.1, fence.z },
			Color = PARK.Fence,
			Material = Enum.Material.Wood,
		})
		local half = fence.length / 2 - 0.3
		for _, sign in ipairs({ -1, 1 }) do
			local px, pz = fence.x, fence.z
			if fence.along == "X" then
				px = fence.x + sign * half
			else
				pz = fence.z + sign * half
			end
			makePart(folder, {
				Name = "FencePost",
				Size = { 0.45, 2.6, 0.45 },
				Pos = { px, 1.3, pz },
				Color = PARK.Fence,
				Material = Enum.Material.Wood,
			})
		end
	end

	local gazebo = PARK_GAZEBO
	makePart(folder, {
		Name = "GazeboFloor",
		Size = { gazebo.floor, 0.4, gazebo.floor },
		Pos = { gazebo.x, 0.2, gazebo.z },
		Color = PARK.Path,
		Material = Enum.Material.Wood,
	})
	local corner = gazebo.floor / 2 - 1.2
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			makeColumn(
				folder,
				"GazeboPillar",
				gazebo.x + sx * corner,
				0.4,
				gazebo.z + sz * corner,
				gazebo.height,
				0.9,
				PARK.Pillar,
				Enum.Material.Wood
			)
		end
	end
	makePart(folder, {
		Name = "GazeboRoof",
		Size = { gazebo.floor + 2, 0.6, gazebo.floor + 2 },
		Pos = { gazebo.x, 0.4 + gazebo.height + 0.3, gazebo.z },
		Color = PARK.Roof,
		Material = Enum.Material.Wood,
	})

	for _, hut in ipairs(PARK_HUTS) do
		makePart(folder, {
			Name = "HutBody",
			Size = { hut.w, hut.h, hut.d },
			Pos = { hut.x, hut.h / 2, hut.z },
			Color = PARK.Wood,
			Material = Enum.Material.Wood,
		})
		makePart(folder, {
			Name = "HutRoof",
			Size = { hut.w + 1.6, 0.8, hut.d + 1.6 },
			Pos = { hut.x, hut.h + 0.4, hut.z },
			Color = PARK.Roof,
			Material = Enum.Material.Wood,
		})
		makePart(folder, {
			Name = "HutDoor",
			Size = { 1.8, hut.h * 0.55, 0.16 },
			Pos = { hut.x, hut.h * 0.28, hut.z - hut.d / 2 - 0.08 },
			Color = PARK.Door,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end

	for _, flower in ipairs(PARK_FLOWERS) do
		makePart(folder, {
			Name = "Flower",
			Size = { 1.6, 0.7, 1.6 },
			Pos = { flower.x, 0.35, flower.z },
			Color = PARK[flower.color],
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end

	for _, lamp in ipairs(PARK_LAMPS) do
		makeColumn(folder, "LampPole", lamp.x, PARK_GRASS_TOP, lamp.z, 8, 0.45, PARK.Pole)
		makePart(folder, {
			Name = "Lamp",
			Size = { 1.4, 0.5, 1.4 },
			Pos = { lamp.x, 8.3, lamp.z },
			Color = PARK.Lamp,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
	end
end

local function buildParkPlayerSpawn(map)
	local spawn = makePart(map, {
		Name = "PlayerSpawn",
		ClassName = "SpawnLocation",
		Size = { PARK_PLAYER_SPAWN.size, 1, PARK_PLAYER_SPAWN.size },
		Pos = { PARK_PLAYER_SPAWN.x, PARK_PLAZA_TOP + 0.5, PARK_PLAYER_SPAWN.z },
		Color = PARK.SpawnPad,
		Transparency = 0.25,
	})
	spawn.Neutral = true
	return spawn
end

-- 広いパークを作り直す。戻り値は集計（Part 数・出現ポイント数・マップ名）
function MapBuilder.BuildPark()
	clearExistingMap()
	local map = Instance.new("Folder")
	map.Name = MapBuilder.MapFolderName

	buildParkGround(map)
	buildParkBoundary(map)
	buildParkProps(map)
	buildParkPlayerSpawn(map)
	local spawns = buildItemSpawns(MapBuilder.ParkSpawnPositions())

	map.Parent = workspace
	spawns.Parent = workspace
	MapBuilder.CurrentMap = "Park"

	return {
		PartCount = partCount,
		ClimbableBuildings = 0,
		ItemSpawns = #PARK_SPAWNS,
		MapId = "Park",
	}
end

---------------------------------------------------------------------
-- 公開関数
---------------------------------------------------------------------

-- 渋谷のマップ一式を作り直す。戻り値は集計（Part 数・屋上に登れる建物の数）
-- ラウンドの交互には進めない（起動時の1回目は、この関数のまま渋谷になる）。
function MapBuilder.Build()
	clearExistingMap()
	local map = Instance.new("Folder")
	map.Name = MapBuilder.MapFolderName

	buildGround(map)
	buildCrosswalks(map)
	buildBoundary(map)
	local climbable = buildBuildings(map)
	buildProps(map)
	buildPlayerSpawn(map)
	local spawns = buildItemSpawns(MapBuilder.ItemSpawnPositions())

	-- 中身を作り終えてから Workspace に置く（1回でまとめて反映される）
	map.Parent = workspace
	spawns.Parent = workspace
	MapBuilder.CurrentMap = "Shibuya"

	return {
		PartCount = partCount,
		ClimbableBuildings = climbable,
		ItemSpawns = #ITEM_SPAWNS,
		MapId = "Shibuya",
	}
end

-- ラウンドごとに呼ぶ。1回目は渋谷、2回目はパーク、以降は交互。
-- Build() 自体はこの回数を進めない（起動時に渋谷を作っても、最初のラウンドは渋谷のまま）。
local mapTurn = 0

function MapBuilder.BuildNextRound()
	mapTurn = mapTurn + 1
	if mapTurn % 2 == 1 then
		return MapBuilder.Build()
	end
	return MapBuilder.BuildPark()
end

return MapBuilder
