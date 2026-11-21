-- ZoneManager: 縮小エリア（ゾーン）の管理（判定はすべてサーバー）
--
-- ラウンド中、円形のエリアが試合時間の80%をかけて縮み続ける。
-- エリアの外に出続けると専用スタミナ（ZoneStamina）が減り、0 になると
-- エリアの中へ戻される。脱落にはならない（小さい子でも遊び続けられる）。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GameState = require(script.Parent:WaitForChild("GameState"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local ZoneManager = {}

local active = false
local center = Vector3.new(0, 0, 0) -- エリアの中心（Y は壁とリスポーンの高さ用）
local startRadius = 0               -- ラウンド開始時点の半径
local currentRadius = 0             -- 今の半径
local roundDuration = 0             -- 今ラウンドの試合時間（秒）
local startClock = 0                -- ラウンド開始時刻（GameState.Now 基準）
local lastCheckClock = 0            -- 前回 内外判定をした時刻
local wallPart = nil

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
	local shrinkTime = duration * Config.ZoneShrinkEndRatio
	if shrinkTime <= 0 or elapsedTime >= shrinkTime then
		return Config.ZoneEndRadius
	end
	local ratio = math.max(0, elapsedTime) / shrinkTime
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

local function updateWall()
	if not wallPart then
		wallPart = Instance.new("Part")
		wallPart.Name = "ZoneWall"
		wallPart.Shape = Enum.PartType.Cylinder
		wallPart.Anchored = true
		wallPart.CanCollide = false
		wallPart.CanQuery = false
		wallPart.Material = Enum.Material.Neon
		wallPart.Color = Config.ZoneWallColor
		wallPart.Transparency = Config.ZoneWallTransparency
		wallPart.Parent = workspace
	end
	local diameter = currentRadius * 2
	wallPart.Size = Vector3.new(Config.ZoneWallHeight, diameter, diameter)
	-- 円柱は横向き（軸が X 方向）が既定なので、Z 軸まわりに90度回して縦向きにする
	wallPart.CFrame = CFrame.new(center.X, center.Y + Config.ZoneWallHeight / 2, center.Z)
		* CFrame.Angles(0, 0, math.rad(90))
end

local function removeWall()
	if wallPart then
		wallPart:Destroy()
		wallPart = nil
	end
end

---------------------------------------------------------------------
-- エリア内へのリスポーン（スタミナが 0 になったとき）
---------------------------------------------------------------------

local function respawnInside(player)
	local character = player.Character
	if not character then
		return
	end
	local angle = math.random() * math.pi * 2
	local dist = math.random() * currentRadius * 0.7 -- 中心寄りに戻す
	local position = Vector3.new(
		center.X + math.cos(angle) * dist,
		center.Y + Config.ItemHeightOffset,
		center.Z + math.sin(angle) * dist
	)
	character:PivotTo(CFrame.new(position))
end

---------------------------------------------------------------------
-- 内外判定とスタミナ
---------------------------------------------------------------------

local function sendZoneUpdate(player, stamina, isOutside)
	if not player or (type(player) == "table" and player.IsBot == true) or not player.Parent then
		return
	end
	Remotes.ZoneUpdate:FireClient(player, {
		Radius = currentRadius,
		Stamina = stamina,
		MaxStamina = Config.ZoneStaminaMax,
		IsOutside = isOutside,
	})
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

			if isOutside then
				data.ZoneStamina = math.max(0, data.ZoneStamina - Config.ZoneDrainPerSecond * step)
				if data.ZoneStamina <= 0 then
					respawnInside(player)
					data.ZoneStamina = Config.ZoneStaminaMax
					isOutside = false
					Remotes.NotifyPlayer(player, "エリアの外に長くいたので、中へ戻された！")
				end
			else
				data.ZoneStamina = math.min(
					Config.ZoneStaminaMax,
					data.ZoneStamina + Config.ZoneRegenPerSecond * step
				)
			end

			sendZoneUpdate(player, data.ZoneStamina, isOutside)
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

	local cx, cy, cz, radius = ZoneManager.ComputeGeometry(points, isFallback)
	center = Vector3.new(cx, cy, cz)
	startRadius = radius
	currentRadius = radius
	roundDuration = duration
	startClock = GameState.Now()
	lastCheckClock = startClock
	active = true

	for _, player in ipairs(GameState.ParticipantList()) do
		GameState.GetData(player).ZoneStamina = Config.ZoneStaminaMax
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
	removeWall()
end

return ZoneManager
