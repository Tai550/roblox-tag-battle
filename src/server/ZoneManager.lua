-- ZoneManager: 縮小エリア（ゾーン）の管理（判定はすべてサーバー）
--
-- ラウンド中、円形のエリアが試合時間の80%をかけて縮み続ける。
-- エリアの外に出続けると専用スタミナ（ZoneStamina）が減り、0 になると
-- 中央へ強制送還される。送還は Config.ZoneMaxReturns 回まで。その次は脱落（観戦）。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GameState = require(script.Parent:WaitForChild("GameState"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Leaderstats = require(script.Parent:WaitForChild("Leaderstats"))

local ZoneManager = {}

local active = false
local center = Vector3.new(0, 0, 0) -- エリアの中心（Y は壁とリスポーンの高さ用）
local startRadius = 0               -- ラウンド開始時点の半径
local currentRadius = 0             -- 今の半径
local roundDuration = 0             -- 今ラウンドの試合時間（秒）
local startClock = 0                -- ラウンド開始時刻（GameState.Now 基準）
local lastCheckClock = 0            -- 前回 内外判定をした時刻
local wallModel = nil  -- 壁のパネルをまとめた Model

-- 脱落したときに呼ぶ関数（RoundManager が設定し、ラウンド終了なら true を返す）
ZoneManager.OnEliminate = nil
local wallPanels = {}  -- 円周に並べた薄いパネル
local skySpawnPoints = nil

---------------------------------------------------------------------
-- 計算だけの関数（テストからも呼べるよう、状態に触らない形で公開）
---------------------------------------------------------------------

-- 出現ポイントからエリアの中心と開始半径を決める。
-- 戻り値: centerX, centerY, centerZ, startRadius
--   中心は出現ポイントの平均（XZ平面が主、高さも平均を使う）
--   開始半径は「中心から一番遠いポイントまでの距離 + 余裕」を Min/Max で丸める
--   予備ポイントだけのマップでは Config.ZoneFallbackRadius を使う
function ZoneManager.ComputeGeometry(points, isFallback)
	if #points == 0 then
		local c = Config.FallbackSpawnCenter
		return c.X, c.Y, c.Z, Config.ZoneFallbackRadius
	end

	local sumX, sumY, sumZ = 0, 0, 0
	for _, point in ipairs(points) do
		sumX = sumX + point.Position.X
		sumY = sumY + point.Position.Y
		sumZ = sumZ + point.Position.Z
	end
	local cx = sumX / #points
	local cy = sumY / #points
	local cz = sumZ / #points

	if isFallback then
		return cx, cy, cz, Config.ZoneFallbackRadius
	end

	local maxDist = 0
	for _, point in ipairs(points) do
		local dx = point.Position.X - cx
		local dz = point.Position.Z - cz
		local dist = math.sqrt(dx * dx + dz * dz)
		if dist > maxDist then
			maxDist = dist
		end
	end

	local radius = maxDist + Config.ZoneStartRadiusPadding
	radius = math.max(Config.ZoneStartRadiusMin, math.min(Config.ZoneStartRadiusMax, radius))
	return cx, cy, cz, radius
end

-- 経過時間から今の半径を返す。試合時間の ZoneShrinkEndRatio まで一定速度で縮み、
-- その後は ZoneEndRadius で固定される
function ZoneManager.RadiusAt(elapsedTime, duration, fromRadius)
	local startTime = duration * Config.ZoneShrinkStartRatio
	local endTime = duration * Config.ZoneShrinkEndRatio
	if elapsedTime <= startTime then
		return fromRadius -- 序盤は縮まない
	end
	if endTime <= startTime or elapsedTime >= endTime then
		return Config.ZoneEndRadius
	end
	local ratio = (elapsedTime - startTime) / (endTime - startTime)
	return fromRadius + (Config.ZoneEndRadius - fromRadius) * ratio
end

-- XZ平面で、位置が円の内側かどうか（境界上は内側扱い）
function ZoneManager.IsInsideXZ(cx, cz, radius, position)
	local dx = position.X - cx
	local dz = position.Z - cz
	return (dx * dx + dz * dz) <= radius * radius
end

---------------------------------------------------------------------
-- 状態の取得（ItemManager などから使う）
---------------------------------------------------------------------

function ZoneManager.IsActive()
	return active
end

function ZoneManager.GetCenter()
	return center
end

function ZoneManager.GetRadius()
	return currentRadius
end

function ZoneManager.IsShrunk()
	return active and currentRadius < startRadius
end

-- 今のエリアの内側かどうか。エリアが動いていない間は常に true（制限なし）
function ZoneManager.IsInside(position)
	if not active then
		return true
	end
	return ZoneManager.IsInsideXZ(center.X, center.Z, currentRadius, position)
end

---------------------------------------------------------------------
-- 壁の見た目（大きな円柱。再利用し、ラウンド終了で消す）
---------------------------------------------------------------------

local function makePanel()
	local panel = Instance.new("Part")
	panel.Anchored = true
	panel.CanCollide = false
	panel.CanQuery = false
	panel.CanTouch = false
	panel.CastShadow = false
	panel.Material = Enum.Material.Neon
	panel.Color = Config.ZoneWallColor
	panel.Transparency = Config.ZoneWallTransparency
	return panel
end

-- 壁は「薄いパネルを円周に並べた輪」で作る。
-- 中身の詰まった円柱にすると、エリアの中にいる間ずっと画面が壁の色に染まるため。
local function updateWall()
	if not wallModel then
		wallModel = Instance.new("Model")
		wallModel.Name = "ZoneWall"
		wallPanels = {}
		for i = 1, Config.ZoneWallSegments do
			local panel = makePanel()
			panel.Name = "Panel" .. i
			panel.Parent = wallModel
			wallPanels[i] = panel
		end
		wallModel.Parent = workspace
	end
	local count = #wallPanels
	local step = math.pi * 2 / count
	-- 隣のパネルとすき間ができないよう、弦の長さより少しだけ長くする
	local width = 2 * currentRadius * math.sin(step / 2) + 0.5
	local y = center.Y + Config.ZoneWallHeight / 2
	for i, panel in ipairs(wallPanels) do
		local angle = (i - 1) * step
		panel.Size = Vector3.new(width, Config.ZoneWallHeight, 0.4)
		-- パネルのローカル X 軸が円の接線方向を向くよう、Y 軸まわりに回す
		panel.CFrame = CFrame.new(
			center.X + math.cos(angle) * currentRadius,
			y,
			center.Z + math.sin(angle) * currentRadius
		) * CFrame.Angles(0, -angle - math.pi / 2, 0)
	end
end

local function removeWall()
	if wallModel then
		wallModel:Destroy()
		wallModel = nil
		wallPanels = {}
	end
end

---------------------------------------------------------------------
-- 中央への強制送還（スタミナが 0 になったとき）
---------------------------------------------------------------------

local function respawnInside(player, nearCenter)
	local character = player.Character
	if not character then
		return
	end
	local angle = math.random() * math.pi * 2
	local dist = nearCenter and 0 or math.min(Config.ZoneReturnRadius, currentRadius * 0.7) -- 中央のまわりに戻す
	local x = center.X + math.cos(angle) * dist
	local z = center.Z + math.sin(angle) * dist
	local y = center.Y + Config.ItemHeightOffset
	if skySpawnPoints then
		-- 空中マップでは、ランダムな座標が空中にならないよう、エリア内の出現ポイントに戻す
		local points = {}
		local nearest, nearestDistance
		for _, point in ipairs(skySpawnPoints) do
			if nearCenter then
				local offset = point.Position - center
				local distance = offset.X * offset.X + offset.Z * offset.Z
				if not nearestDistance or distance < nearestDistance then
					nearest, nearestDistance = point, distance
				end
			elseif ZoneManager.IsInsideXZ(center.X, center.Z, currentRadius, point.Position) then
				table.insert(points, point)
			end
		end
		local point = nearest or points[math.random(1, math.max(1, #points))]
		if not point then
			return
		end
		local root = GameState.GetRootPart(player)
		if root then
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		end
		character:PivotTo(CFrame.new(point.Position + Vector3.new(0, Config.ItemHeightOffset + 1, 0)))
		return
	end
	-- 障害物の中に埋まらないよう、上から真下に光線を飛ばして足場の上に置く
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, wallModel }
	local from = Vector3.new(x, center.Y + Config.RespawnRayHeight, z)
	local hit = workspace:Raycast(from, Vector3.new(0, -Config.RespawnRayHeight * 2, 0), params)
	if hit then
		y = hit.Position.Y + Config.ItemHeightOffset
	end
	if nearCenter then
		local root = GameState.GetRootPart(player)
		if root then
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		end
	end
	character:PivotTo(CFrame.new(x, y, z))
end

function ZoneManager.WarpToCenter(player)
	local character = player.Character
	local root = GameState.GetRootPart(player)
	if not active or not character or not root then
		return false
	end

	local excluded = { character }
	if wallModel then
		table.insert(excluded, wallModel)
	end
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(excluded, other.Character)
		end
	end
	for _, other in ipairs(GameState.ParticipantList()) do
		if other.Character then
			table.insert(excluded, other.Character)
		end
	end

	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = excluded
	ray.RespectCanCollide = true
	ray.CollisionGroup = root.CollisionGroup
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	overlap.CollisionGroup = root.CollisionGroup

	local candidates = { center }
	if skySpawnPoints then
		for _, point in ipairs(skySpawnPoints) do
			table.insert(candidates, point.Position)
		end
	end
	local searchRadius = math.min(Config.ZoneReturnRadius, currentRadius)
	for radius = 4, searchRadius, 4 do
		for index = 0, 7 do
			local angle = index * math.pi / 4
			table.insert(candidates, center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
		end
	end
	local function distance(position)
		local offset = position - center
		return offset.X * offset.X + offset.Z * offset.Z
	end
	table.sort(candidates, function(a, b)
		return distance(a) < distance(b)
	end)

	local bounds, size = character:GetBoundingBox()
	local pivot = character:GetPivot()
	local clearance = 0.1
	for _, candidate in ipairs(candidates) do
		if not ZoneManager.IsInsideXZ(center.X, center.Z, currentRadius, candidate) then
			continue
		end
		local from = candidate + Vector3.new(0, Config.RespawnRayHeight, 0)
		local hit = workspace:Raycast(from, Vector3.new(0, -Config.RespawnRayHeight * 2, 0), ray)
		if not hit or not hit.Instance.CanCollide or hit.Normal.Y < 0.5 then
			continue
		end
		local boxPosition = hit.Position + Vector3.new(0, size.Y / 2 + clearance, 0)
		local occupied = false
		local offset = boxPosition - bounds.Position
		for _, part in ipairs(workspace:GetPartBoundsInBox(bounds + offset, size, overlap)) do
			local model = part:FindFirstAncestorOfClass("Model")
			if part.CanCollide or (model and model:FindFirstChildOfClass("Humanoid")) then
				occupied = true
				break
			end
		end
		if not occupied then
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			character:PivotTo(pivot + offset)
			return true
		end
	end
	return false
end

function ZoneManager.ReturnTaggerToCenter(player)
	if active and not ZoneManager.WarpToCenter(player) then
		respawnInside(player, true)
	end
end

---------------------------------------------------------------------
-- 内外判定とスタミナ
---------------------------------------------------------------------

local function guardUntil(data)
	if data.BeastUsed == "Bastet" then
		return math.max(data.ZoneGuardUntil, data.BeastEffectUntil)
	end
	return data.ZoneGuardUntil
end

local function sendZoneUpdate(player, data, isOutside)
	if Remotes.IsRealPlayer(player) then
		Remotes.ZoneUpdate:FireClient(player, {
			Radius = currentRadius,
			Stamina = data.ZoneStamina,
			MaxStamina = Config.ZoneStaminaMax,
			IsOutside = isOutside,
			Returns = data.ZoneReturns,
			MaxReturns = Config.ZoneMaxReturns,
			GuardLeft = math.max(0, guardUntil(data) - GameState.Now()),
		})
	end
end
ZoneManager.SendZoneUpdate = function(player)
	sendZoneUpdate(player, GameState.GetData(player), false)
end

-- 送還の回数を使い切っているか（計算だけの関数）
function ZoneManager.ShouldEliminate(returnsSoFar)
	return returnsSoFar >= Config.ZoneMaxReturns
end

local function checkPlayers(step)
	for _, player in ipairs(GameState.ParticipantList()) do
		if GameState.IsAlive(player) then
			local data = GameState.GetData(player)
			local root = GameState.GetRootPart(player)
			local isOutside = false
			if root then
				isOutside = not ZoneManager.IsInsideXZ(center.X, center.Z, currentRadius, root.Position)
			end

			local guarded = guardUntil(data) > GameState.Now()
			if isOutside and not guarded then
				data.ZoneStamina = math.max(0, data.ZoneStamina - Config.ZoneDrainPerSecond * step)
				if data.ZoneStamina <= 0 then
					data.ZoneStamina = Config.ZoneStaminaMax
					isOutside = false
					if ZoneManager.ShouldEliminate(data.ZoneReturns) then
						if ZoneManager.OnEliminate and ZoneManager.OnEliminate(player) then
							return
						end
					else
						data.ZoneReturns = data.ZoneReturns + 1
						Leaderstats.Set(player, "Returns", data.ZoneReturns)
						respawnInside(player)
						local left = Config.ZoneMaxReturns - data.ZoneReturns
						if left > 0 then
							Remotes.NotifyPlayer(player, string.format("強制送還！ あと%d回で脱落", left + 1))
						else
							Remotes.NotifyPlayer(player, "強制送還！ 次にエリア外で力尽きたら脱落")
						end
					end
				end
			else
				data.ZoneStamina = math.min(
					Config.ZoneStaminaMax,
					data.ZoneStamina + Config.ZoneRegenPerSecond * step
						* Config.ComboMultiplier(data.ActiveCombos, "StaminaRegenMultiplier")
				)
			end

			sendZoneUpdate(player, data, isOutside)
		end
	end
end

---------------------------------------------------------------------
-- 外部（RoundManager）から呼ぶ関数
---------------------------------------------------------------------

-- ラウンド開始時に呼ぶ。duration は投票で決まった試合時間（秒）
function ZoneManager.Start(duration)
	-- ItemManager との循環参照を避けるため、ここで遅れて require する
	local ItemManager = require(script.Parent:WaitForChild("ItemManager"))
	local points, isFallback = ItemManager.GetSpawnPoints()
	skySpawnPoints = workspace:GetAttribute("CurrentMap") == "Sky" and points or nil

	local cx, cy, cz, radius = ZoneManager.ComputeGeometry(points, isFallback)
	-- 全マップの歩行範囲は原点を中心とする正方形。最も遠い角を開始ゾーンに含める。
	local map = workspace:FindFirstChild("Map")
	local half = map and map:GetAttribute("WalkableHalfExtent")
	if half then
		local dx = half + math.abs(cx)
		local dz = half + math.abs(cz)
		radius = math.max(radius, math.ceil(math.sqrt(dx * dx + dz * dz)))
	end
	center = Vector3.new(cx, cy, cz)
	startRadius = radius
	currentRadius = radius
	roundDuration = duration
	startClock = GameState.Now()
	lastCheckClock = startClock
	active = true

	for _, player in ipairs(GameState.ParticipantList()) do
		local data = GameState.GetData(player)
		data.ZoneStamina = Config.ZoneStaminaMax
		data.ZoneReturns = 0
	end

	updateWall()
	checkPlayers(0) -- 初回の状態（半径・スタミナ）を送る
end

-- RoundManager のループから定期的に呼ぶ：壁の大きさとスタミナを進める
function ZoneManager.Tick()
	if not active then
		return
	end
	local now = GameState.Now()
	currentRadius = ZoneManager.RadiusAt(now - startClock, roundDuration, startRadius)
	updateWall()

	if now - lastCheckClock >= Config.ZoneCheckInterval then
		local step = now - lastCheckClock
		lastCheckClock = now
		checkPlayers(step)
	end
end

-- ラウンド終了時に呼ぶ
function ZoneManager.Stop()
	active = false
	skySpawnPoints = nil
	removeWall()
end

return ZoneManager
