-- RoundManager のラウンドループで帯電床と落雷を更新する。
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GameState = require(script.Parent:WaitForChild("GameState"))
local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))

local VoltGimmicks = {}
local round
local warningColor = Color3.fromRGB(255, 133, 25)
local activeColor = Color3.fromRGB(84, 225, 255)

local function isVoltRound()
	return GameState.Phase == "Round" and workspace:GetAttribute("CurrentGimmick") == "Volt"
end

function VoltGimmicks.Stop()
	if round and round.map.Parent == workspace then
		for _, area in ipairs(round.areas) do
			area.Transparency = 1
		end
		round.marker.Transparency = 1
		round.bolt.Transparency = 1
	end
	round = nil
end

function VoltGimmicks.Start(now)
	VoltGimmicks.Stop()
	if not isVoltRound() then
		return
	end
	local map = workspace:FindFirstChild(MapBuilder.MapFolderName)
	local effects = map and map:FindFirstChild("VoltEffects")
	if not effects then
		return
	end
	round = {
		map = map,
		floor = map:FindFirstChild("MetalFloor"),
		areas = effects:FindFirstChild("FloorAreas"):GetChildren(),
		marker = effects:FindFirstChild("LightningMarker"),
		bolt = effects:FindFirstChild("LightningBolt"),
		floorPhase = "Safe",
		floorDeadline = now + Config.VoltFloorSafeTime,
		nextWarning = now + Config.VoltLightningInterval,
	}
end

local function updateFloor(now)
	if now < round.floorDeadline then
		return
	end
	-- 予兆を実際に表示した時刻から測り、サーバーが遅れても予兆を飛ばさない。
	if round.floorPhase == "Safe" then
		round.floorPhase = "Warning"
		round.floorDeadline = now + Config.VoltFloorWarningTime
	elseif round.floorPhase == "Warning" then
		round.floorPhase = "Active"
		round.floorDeadline = now + Config.VoltFloorActiveTime
	else
		round.floorPhase = "Safe"
		round.floorDeadline = now + Config.VoltFloorSafeTime
	end
	for _, area in ipairs(round.areas) do
		area.Color = round.floorPhase == "Warning" and warningColor or activeColor
		area.Transparency = round.floorPhase == "Safe" and 1 or (round.floorPhase == "Warning" and 0.35 or 0.1)
	end
end

local function updateLightning(now)
	if round.strikeAt then
		if now < round.strikeAt then
			return false
		end
		round.strikeAt = nil
		round.flashUntil = now + Config.VoltLightningFlashTime
		round.marker.Color = activeColor
		round.bolt.Transparency = 0.1
		return true
	end
	if round.flashUntil then
		if now < round.flashUntil then
			return false
		end
		round.flashUntil = nil
		round.marker.Transparency = 1
		round.bolt.Transparency = 1
	end
	if now >= round.nextWarning then
		local floor = round.floor
		local radius = Config.VoltLightningRadius
		local x = floor.Position.X + (math.random() * 2 - 1) * (floor.Size.X / 2 - radius)
		local z = floor.Position.Z + (math.random() * 2 - 1) * (floor.Size.Z / 2 - radius)
		round.marker.Position = Vector3.new(x, round.marker.Position.Y, z)
		round.bolt.Position = Vector3.new(x, round.bolt.Position.Y, z)
		round.marker.Color = warningColor
		round.marker.Transparency = 0.35
		round.strikeAt = now + Config.VoltLightningWarningTime
		round.nextWarning = now + Config.VoltLightningInterval
	end
	return false
end

local function isOverChargedFloor(position)
	for _, area in ipairs(round.areas) do
		if math.abs(position.X - area.Position.X) <= area.Size.X / 2
			and math.abs(position.Z - area.Position.Z) <= area.Size.Z / 2 then
			return true
		end
	end
	return false
end

function VoltGimmicks.Tick(now)
	if not round then
		return
	end
	if not isVoltRound() or round.map.Parent ~= workspace then
		VoltGimmicks.Stop()
		return
	end
	updateFloor(now)
	local struck = updateLightning(now)
	local active = round.floorPhase == "Active"
	if not struck and not active then
		return
	end
	local floorTop = round.floor.Position.Y + round.floor.Size.Y / 2
	for _, player in ipairs(GameState.ParticipantList()) do
		local root = GameState.GetRootPart(player)
		if root then
			local position = root.Position
			local height = position.Y - floorTop
			local dx = position.X - round.marker.Position.X
			local dz = position.Z - round.marker.Position.Z
			if height >= 0 and ((active and height <= Config.VoltFloorHitHeight and isOverChargedFloor(position))
				or (struck and height <= Config.VoltLightningHeight and dx * dx + dz * dz <= Config.VoltLightningRadius ^ 2)) then
				GameState.TryVoltStun(player)
			end
		end
	end
end

return VoltGimmicks
