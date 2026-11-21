-- BotManager: 人数が足りないラウンドをボット（NPC）で補う
-- ボットは Player ではなく { IsBot = true, ... } のテーブル。GameState の辞書キーに使う。
-- 強さは人間の平均段位から表を引くだけ（機械学習ではない）。
-- 経路は PathfindingService。高所への経路がなければ、台の縁からのジャンプを試す。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GameState = require(script.Parent:WaitForChild("GameState"))
local RankManager = require(script.Parent:WaitForChild("RankManager"))
local ItemManager = require(script.Parent:WaitForChild("ItemManager"))
local ZoneManager = require(script.Parent:WaitForChild("ZoneManager"))
local DeckManager = require(script.Parent:WaitForChild("DeckManager"))
local TaggerLook = require(script.Parent:WaitForChild("TaggerLook"))

local BotManager = {}

local HIP_HEIGHT = 3
local COLOR_HEAD = Color3.fromRGB(214, 218, 224)
local COLOR_TORSO = Color3.fromRGB(168, 176, 188)
local COLOR_LIMB = Color3.fromRGB(140, 148, 160)

local activeBots = {}
local roundRepathInterval = Config.BotStrengthByTier[1].RepathInterval

---------------------------------------------------------------------
-- 補充人数と強さ（計算だけ。テストから呼ぶ）
---------------------------------------------------------------------

-- 人間が MinPlayers 未満、または目標以上、または無効なら 0。
function BotManager.CountToSpawn(humanCount)
	if Config.BotsEnabled == false then
		return 0
	end
	humanCount = tonumber(humanCount) or 0
	if humanCount < Config.MinPlayers then
		return 0
	end
	local target = tonumber(Config.BotFillTarget) or 0
	if humanCount >= target then
		return 0
	end
	return target - humanCount
end

-- RankTiers の位置（1 = ブロンズ）。Config.TierForRP と同じ段を、並びの番号で返す。
function BotManager.TierIndexForRP(rp)
	rp = tonumber(rp) or 0
	local bestIndex = 1
	local bestMin = -1
	for index, tier in ipairs(Config.RankTiers) do
		if rp >= tier.MinRP and tier.MinRP >= bestMin then
			bestIndex = index
			bestMin = tier.MinRP
		end
	end
	return bestIndex
end

-- 段位番号の平均を四捨五入して、表の範囲に収める。空ならブロンズ。
function BotManager.AverageTierIndex(indices)
	if type(indices) ~= "table" or #indices == 0 then
		return 1
	end
	local sum = 0
	for _, index in ipairs(indices) do
		sum = sum + (tonumber(index) or 1)
	end
	local rounded = math.floor(sum / #indices + 0.5)
	if rounded < 1 then
		rounded = 1
	end
	local maxIndex = #Config.RankTiers
	if rounded > maxIndex then
		rounded = maxIndex
	end
	return rounded
end

-- 戻り値: 歩く速さの倍率, 経路を引き直す間隔（秒）
-- 倍率は Config.BotSpeedMultiplierCap（初期 1.15）で止める。
function BotManager.StrengthForTierIndex(tierIndex)
	local rows = Config.BotStrengthByTier
	local index = math.floor(tonumber(tierIndex) or 1)
	if index < 1 then
		index = 1
	end
	if index > #rows then
		index = #rows
	end
	local row = rows[index]
	local speed = row.SpeedMultiplier or 1
	local cap = Config.BotSpeedMultiplierCap
	if type(cap) == "number" and speed > cap then
		speed = cap
	end
	if speed < 0 then
		speed = 0
	end
	local interval = row.RepathInterval or 1
	if interval < 0.2 then
		interval = 0.2
	end
	return speed, interval
end

-- アイテムを使うか。スモークは画面への Remote なので、ボットは使わない。
function BotManager.ShouldUseItem(itemId, isTagger, distance)
	if itemId == "Smoke" then
		return false
	end
	if type(distance) ~= "number" or distance == math.huge then
		return false
	end
	if itemId == "Dash" then
		if isTagger then
			return distance >= Config.BotTaggerDashDistance
		end
		return distance <= Config.BotDashDistance
	elseif itemId == "Shield" then
		return isTagger ~= true and distance <= Config.BotShieldDistance
	elseif itemId == "Star" then
		return isTagger ~= true and distance <= Config.BotStarDistance
	elseif itemId == "Warp" then
		return distance <= Config.BotWarpDistance
	elseif itemId == "Banana" then
		return distance <= Config.BotBananaDistance
	end
	return false
end

-- 行き詰まり。戻り値: 新しい累計秒, ジャンプするか
function BotManager.UpdateStuck(stuckTime, moved, dt, speedLimit, timeLimit)
	stuckTime = stuckTime or 0
	dt = dt or 0
	if dt <= 0 then
		return stuckTime, false
	end
	local limit = speedLimit or Config.BotStuckSpeed
	if moved <= limit * dt then
		stuckTime = stuckTime + dt
	else
		stuckTime = 0
	end
	local need = timeLimit or Config.BotStuckTime
	if stuckTime >= need then
		return 0, true
	end
	return stuckTime, false
end

local function clampInside(x, z, zx, zz, limit)
	local dx = x - zx
	local dz = z - zz
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist <= limit or dist < 0.001 then
		return x, z
	end
	return zx + dx / dist * limit, zz + dz / dist * limit
end

local function inwardPoint(x, z, zx, zz, desired)
	local dx = x - zx
	local dz = z - zz
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < 0.001 then
		return zx, zz
	end
	if dist <= desired then
		return x, z
	end
	return zx + dx / dist * desired, zz + dz / dist * desired
end

-- 戻り値: goalX, goalZ, 理由, 対象（追跡またはアイテム）
function BotManager.ChooseGoal(ctx)
	local x = ctx.X or 0
	local z = ctx.Z or 0
	local zoneActive = ctx.ZoneActive == true
	local radius = ctx.ZoneRadius or 0
	local zx = ctx.ZoneX or 0
	local zz = ctx.ZoneZ or 0
	local edgeRatio = ctx.ZoneShrunk and Config.BotShrunkZoneEdgeRatio or Config.BotZoneEdgeRatio

	if zoneActive and ctx.Role ~= "Tagger" and radius > 0 then
		local dx = x - zx
		local dz = z - zz
		local dist = math.sqrt(dx * dx + dz * dz)
		local edge = radius * edgeRatio
		if dist > edge then
			local ratio = ctx.ZoneShrunk and Config.BotShrunkZoneInwardRatio or Config.BotZoneInwardRatio
			local gx, gz = inwardPoint(x, z, zx, zz, radius * ratio)
			return gx, gz, "zone"
		end
	end

	if ctx.Blind then
		local angle = ctx.BlindAngle or 0
		local reach = Config.BotFleeDistance or 28
		local gx = x + math.cos(angle) * reach
		local gz = z + math.sin(angle) * reach
		if zoneActive and radius > 0 then
			gx, gz = clampInside(gx, gz, zx, zz, radius * edgeRatio)
		end
		return gx, gz, "blind"
	end

	if ctx.Role == "Tagger" then
		local nearest = nil
		local best = math.huge
		for _, runner in ipairs(ctx.Runners or {}) do
			local dx = (runner.X or 0) - x
			local dz = (runner.Z or 0) - z
			local dy = (runner.Y or ctx.Y or 0) - (ctx.Y or 0)
			local d2 = dx * dx + dy * dy + dz * dz
			if d2 < best then
				best = d2
				nearest = runner
			end
		end
		if nearest then
			return nearest.X or x, nearest.Z or z, "chase", nearest
		end
		return x, z, "idle"
	end

	local taggerDist = nil
	if ctx.TaggerX ~= nil and ctx.TaggerZ ~= nil then
		local dx = x - ctx.TaggerX
		local dz = z - ctx.TaggerZ
		taggerDist = math.sqrt(dx * dx + dz * dz)
	end

	local safe = Config.BotItemSafeDistance or 30
	if (taggerDist == nil or taggerDist >= safe) and type(ctx.Boxes) == "table" then
		local seek = Config.BotItemSeekDistance or 40
		local seek2 = seek * seek
		local nearest = nil
		local best = math.huge
		for _, box in ipairs(ctx.Boxes) do
			local dx = (box.X or 0) - x
			local dz = (box.Z or 0) - z
			local d2 = dx * dx + dz * dz
			if d2 <= seek2 and d2 < best then
				best = d2
				nearest = box
			end
		end
		if nearest then
			return nearest.X or x, nearest.Z or z, "item", nearest
		end
	end

	if taggerDist ~= nil and taggerDist > 0.05 then
		local dx = x - ctx.TaggerX
		local dz = z - ctx.TaggerZ
		local reach = Config.BotFleeDistance or 28
		local gx = x + dx / taggerDist * reach
		local gz = z + dz / taggerDist * reach
		if zoneActive and radius > 0 then
			if ctx.ZoneShrunk then
				gx = gx + (zx - gx) * Config.BotShrunkZoneFleeBias
				gz = gz + (zz - gz) * Config.BotShrunkZoneFleeBias
			end
			gx, gz = clampInside(gx, gz, zx, zz, radius * edgeRatio)
		end
		return gx, gz, "flee"
	end

	return x, z, "idle"
end

---------------------------------------------------------------------
-- 体（コードで組む簡素な人型。鬼の色は TaggerLook が Part を塗る）
---------------------------------------------------------------------

local function botFolder()
	local folder = workspace:FindFirstChild("Bots")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Bots"
		folder.Parent = workspace
	end
	return folder
end

local function findSpawnPart()
	for _, desc in ipairs(workspace:GetDescendants()) do
		if desc.IsA and desc:IsA("SpawnLocation") then
			return desc
		end
	end
	return nil
end

local function standPosition(index, total, spawnPart)
	local x, y, z = 0, 8, 0
	if spawnPart and spawnPart.Position then
		x = spawnPart.Position.X or 0
		y = spawnPart.Position.Y or 0
		z = spawnPart.Position.Z or 0
		local sizeY = 1
		if spawnPart.Size and type(spawnPart.Size.Y) == "number" then
			sizeY = spawnPart.Size.Y
		end
		y = y + sizeY / 2 + HIP_HEIGHT
	else
		local fallback = Config.FallbackSpawnCenter
		if fallback then
			x = fallback.X
			y = fallback.Y + HIP_HEIGHT
			z = fallback.Z
		end
	end
	local slots = math.max(total, 1)
	local angle = ((index - 1) / slots) * math.pi * 2
	local radius = 6
	return x + math.cos(angle) * radius, y, z + math.sin(angle) * radius
end

local function addPart(model, name, size, x, y, z, color, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	part.Massless = name ~= "HumanoidRootPart"
	part.Transparency = transparency or 0
	part.CFrame = CFrame.new(x, y, z)
	part.Position = Vector3.new(x, y, z)
	part.Parent = model
	return part
end

local function weldTo(root, part)
	local weld = Instance.new("WeldConstraint")
	weld.Name = part.Name .. "Weld"
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = root
end

local function buildCharacter(displayName, x, y, z)
	local model = Instance.new("Model")
	model.Name = displayName

	local root = addPart(model, "HumanoidRootPart", Vector3.new(2, 2, 1), x, y, z, COLOR_TORSO, 1)
	addPart(model, "Torso", Vector3.new(2, 2, 1), x, y, z, COLOR_TORSO, 0)
	local head = addPart(model, "Head", Vector3.new(2, 1, 1), x, y + 1.5, z, COLOR_HEAD, 0)
	addPart(model, "Left Arm", Vector3.new(1, 2, 1), x - 1.5, y, z, COLOR_LIMB, 0)
	addPart(model, "Right Arm", Vector3.new(1, 2, 1), x + 1.5, y, z, COLOR_LIMB, 0)
	addPart(model, "Left Leg", Vector3.new(1, 2, 1), x - 0.5, y - 2, z, COLOR_LIMB, 0)
	addPart(model, "Right Leg", Vector3.new(1, 2, 1), x + 0.5, y - 2, z, COLOR_LIMB, 0)

	for _, desc in ipairs(model:GetChildren()) do
		if desc:IsA("BasePart") and desc ~= root then
			weldTo(root, desc)
		end
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.HipHeight = HIP_HEIGHT
	humanoid.Parent = model
	pcall(function()
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.AutomaticScalingEnabled = false
		humanoid.AutoRotate = true
		humanoid.BreakJointsOnDeath = false
	end)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Size = UDim2.new(0, 120, 0, 28)
	billboard.StudsOffset = Vector3.new(0, 1.4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 150
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Text = displayName
	label.TextColor3 = Color3.fromRGB(245, 247, 250)
	label.TextStrokeColor3 = Color3.fromRGB(30, 34, 40)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	model.PrimaryPart = root
	model.Parent = botFolder()

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = false
		end
	end
	-- 近くのプレイヤーに物理が渡ると、サーバーの MoveTo が効かなくなる。サーバー所有を取り直す。
	if type(root.SetNetworkOwner) == "function" then
		task.spawn(function()
			for _ = 1, 8 do
				if root.Parent == nil then
					return
				end
				local ok = pcall(function()
					root:SetNetworkOwner(nil)
				end)
				if ok then
					return
				end
				task.wait(0.15)
			end
		end)
	end
	return model
end

-- Roblox 標準の R15 の体で作る（コードで組んだ体は Humanoid が歩けないため）。
-- 作れない環境（テストのモックなど）では、簡素な体に倒す。
local BOT_COLORS = {
	Color3.fromRGB(255, 120, 120), Color3.fromRGB(120, 180, 255), Color3.fromRGB(255, 210, 90),
	Color3.fromRGB(140, 220, 140), Color3.fromRGB(210, 150, 255), Color3.fromRGB(255, 160, 210),
	Color3.fromRGB(120, 230, 220),
}

local function buildStandardCharacter(index, displayName, x, y, z)
	local ok, model = pcall(function()
		local description = Instance.new("HumanoidDescription")
		if Config.BotMuscular then
			description.WidthScale = 1.3
			description.DepthScale = 1.25
			description.BodyTypeScale = 0
			description.ProportionScale = 0
		end
		local color = BOT_COLORS[(index - 1) % #BOT_COLORS + 1]
		description.HeadColor = Color3.fromRGB(255, 220, 180)
		description.TorsoColor = color
		description.LeftArmColor = color
		description.RightArmColor = color
		description.LeftLegColor = Color3.fromRGB(60, 60, 80)
		description.RightLegColor = Color3.fromRGB(60, 60, 80)
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model or type(model.FindFirstChild) ~= "function" then
		return nil
	end
	model.Name = displayName
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = displayName
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	end
	model:PivotTo(CFrame.new(x, y + 2, z))
	model.Parent = botFolder()
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then
		if Config.BotMuscular then
			root.Size = Vector3.new(2, 2, 1) -- 標準 R15 の当たり判定を維持する
		end
		pcall(function()
			root:SetNetworkOwner(nil) -- 動きはサーバーが決める
		end)
	end
	return model
end

local function createBot(index, total, spawnPart)
	local name = "ボット" .. tostring(index)
	local x, y, z = standPosition(index, total, spawnPart)
	local character = buildStandardCharacter(index, name, x, y, z) or buildCharacter(name, x, y, z)
	local bot = {
		IsBot = true,
		Name = name,
		DisplayName = name,
		UserId = -index,
		Character = character,
		Parent = Players, -- 「まだサーバーにいる」扱い（消すときに nil にする）
		SpeedMultiplier = 1,
		StuckTime = 0,
	}
	GameState.RegisterCharacter(bot, character)
	return bot
end

---------------------------------------------------------------------
-- 経路
---------------------------------------------------------------------

local function computePath(fromPos, toPos)
	local okService, service = pcall(function()
		return game:GetService("PathfindingService")
	end)
	if not okService or service == nil or type(service.CreatePath) ~= "function" then
		return nil
	end
	local created, path = pcall(function()
		return service:CreatePath({
			AgentRadius = MapBuilder.CurrentMap == "Sky" and 1 or 2,
			AgentHeight = 5,
			AgentCanJump = true,
			WaypointSpacing = 4,
		})
	end)
	-- Path は userdata。テーブルかどうかでは判断しない。
	if not created or path == nil or type(path.ComputeAsync) ~= "function" then
		return nil
	end
	local computed = pcall(function()
		path:ComputeAsync(fromPos, toPos)
	end)
	if not computed then
		return nil
	end
	local successStatus = nil
	local statusOk, statusValue = pcall(function()
		return Enum.PathStatus.Success
	end)
	if statusOk then
		successStatus = statusValue
	end
	if successStatus ~= nil and path.Status ~= nil and path.Status ~= successStatus then
		return nil
	end
	if type(path.GetWaypoints) ~= "function" then
		return nil
	end
	local waypoints = nil
	local got = pcall(function()
		waypoints = path:GetWaypoints()
	end)
	if not got or type(waypoints) ~= "table" or #waypoints == 0 then
		return nil
	end
	return waypoints
end

local function moveTo(humanoid, position)
	if humanoid and type(humanoid.MoveTo) == "function" then
		pcall(function()
			humanoid:MoveTo(position)
		end)
	end
end

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function navigationQuery(bot)
	local query = RaycastParams.new()
	query.FilterType = Enum.RaycastFilterType.Exclude
	query.RespectCanCollide = true
	local excluded = { bot.Character }
	for _, player in ipairs(GameState.ParticipantList()) do
		if player ~= bot and player.Character then
			table.insert(excluded, player.Character)
		end
	end
	query.FilterDescendantsInstances = excluded
	return query
end

local function groundAt(position, query)
	local hit = workspace:Raycast(position, Vector3.new(0, -Config.BotApproachProbeDepth, 0), query)
	return hit and hit.Position, hit and hit.Instance
end

function BotManager.PredictPosition(position, velocity)
	if not velocity then
		return position
	end
	local offset = horizontal(velocity) * Config.BotPredictionTime
	if offset.Magnitude > Config.BotPredictionMaxDistance then
		offset = offset.Unit * Config.BotPredictionMaxDistance
	end
	return position + offset
end

-- 比較する目標は一定時間固定する。逃げ手の移動自体をボットの進捗に数えない。
function BotManager.UpdateProgress(bot, position, goal, now)
	local reference = bot.ProgressGoal or goal
	local distance = (position - reference).Magnitude
	if bot.ProgressBest == nil or distance <= bot.ProgressBest - Config.BotProgressDistance then
		bot.ProgressGoal = goal
		bot.ProgressBest = (position - goal).Magnitude
		bot.ProgressAt = now
		return false
	end
	return now - bot.ProgressAt >= Config.BotProgressTimeout
end

local function clearProgress(bot)
	bot.ProgressGoal = nil
	bot.ProgressBest = nil
	bot.ProgressAt = nil
end

-- 高所へは足場の高さが変わる縁を探す。地上での立て直しは周囲の通れる点を探す。
local function approachCandidates(position, goal, jumpHeight, query, zoneCenter, zoneRadius)
	local candidates = {}
	local top = jumpHeight and groundAt(goal, query)
	if jumpHeight and not top then
		return candidates
	end
	local center = top or position
	for index = 0, Config.BotApproachDirections - 1 do
		local angle = index * 2 * math.pi / Config.BotApproachDirections
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		if top then
			local inside = top
			for radius = Config.BotApproachStep, Config.BotApproachRadius, Config.BotApproachStep do
				local sample = groundAt(top + direction * radius + Vector3.new(0, Config.BotApproachProbeHeight, 0), query)
				if sample and top.Y - sample.Y >= Config.BotElevatedThreshold then
					local rise = inside.Y - sample.Y
					if rise <= jumpHeight then
						table.insert(candidates, {
							Position = sample,
							Landing = inside,
							Score = (position - sample).Magnitude + rise,
							Index = index,
						})
					end
					break
				end
				if not sample or math.abs(sample.Y - top.Y) >= Config.BotElevatedThreshold then
					break
				end
				inside = sample
			end
		else
			local offset = direction * (Config.BotApproachRadius / 2)
			local sample = groundAt(center + offset + Vector3.new(0, Config.BotApproachProbeHeight, 0), query)
			local insideZone = sample and (not zoneCenter or ZoneManager.IsInsideXZ(zoneCenter.X, zoneCenter.Z, zoneRadius, sample)
				or horizontal(sample - zoneCenter).Magnitude < horizontal(position - zoneCenter).Magnitude)
			if insideZone and not workspace:Raycast(position, offset, query) then
				table.insert(candidates, {
					Position = sample,
					Score = (sample - goal).Magnitude,
					Index = index,
				})
			end
		end
	end
	table.sort(candidates, function(a, b)
		if a.Score == b.Score then
			return a.Index < b.Index
		end
		return a.Score < b.Score
	end)
	return candidates
end

local function followWaypoints(bot, humanoid, root, target, sky)
	local waypoints = bot.Waypoints
	if waypoints then
		local index = bot.WaypointIndex
		local footY = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
		while waypoints[index] do
			local wp = waypoints[index]
			local delta = root.Position - wp.Position
			local jump = wp.Action == Enum.PathWaypointAction.Jump
			local reach = jump and Config.BotJumpWaypointReach or Config.BotWaypointReach
			if horizontal(delta).Magnitude > reach
				or (not sky and math.abs(footY - wp.Position.Y) > Config.BotWaypointReach
					and not (index == 1 and math.abs(delta.Y) <= Config.BotWaypointReach)) then
				target = wp.Position
				break
			end
			if jump then
				humanoid.Jump = true
			end
			index += 1
		end
		bot.WaypointIndex = index
	end
	moveTo(humanoid, target)
end

local function requestPath(bot, from, target, fallback, goal, candidate)
	if bot.PathComputing then
		return false
	end
	local generation = bot.PathGeneration
	local roundData = GameState.GetData(bot)
	bot.PathComputing = true
	local function isCurrent()
		return bot.Parent and GameState.Phase == "Round" and bot.PathGeneration == generation
			and GameState.GetData(bot) == roundData
	end
	task.spawn(function()
		local waypoints = computePath(from, target)
		local usesFallback = not waypoints and fallback ~= nil
		if usesFallback and isCurrent() then
			waypoints = computePath(from, fallback)
		end
		bot.PathComputing = nil
		if isCurrent() then
			bot.PathResult = {
				Waypoints = waypoints,
				Target = usesFallback and fallback or target,
				UsesFallback = usesFallback,
				Goal = goal,
				Candidate = candidate,
			}
		end
	end)
	return true
end

local function cancelPath(bot)
	bot.PathGeneration = (bot.PathGeneration or 0) + 1
	bot.PathResult = nil
	bot.Waypoints = nil
end

local function startRecovery(bot, humanoid, root, goal, elevated, now, query, zoneCenter, zoneRadius)
	local jumpHeight = elevated and humanoid.JumpHeight
	local attempts
	if elevated then
		local _, platform = groundAt(goal, query)
		attempts = bot.ApproachAttempts
		if not attempts or attempts.Platform ~= platform
			or (attempts.Goal - goal).Magnitude >= Config.BotRepathGoalShift
			or (attempts.Origin - root.Position).Magnitude >= Config.BotApproachRadius + Config.BotRepathGoalShift then
			attempts = { Platform = platform, Goal = goal, Origin = root.Position, Failed = {} }
			bot.ApproachAttempts = attempts
		end
		if attempts.Exhausted then
			return false
		end
	end
	local candidates = approachCandidates(root.Position, goal, jumpHeight, query, zoneCenter, zoneRadius)
	if attempts then
		for index = #candidates, 1, -1 do
			if attempts.Failed[candidates[index].Index] then
				table.remove(candidates, index)
			end
		end
	end
	if #candidates == 0 then
		if attempts then
			attempts.Exhausted = true
		end
		return false
	end
	bot.Recovery = {
		Candidates = candidates,
		Attempts = attempts,
		Index = 1,
		Goal = goal,
		Deadline = now + Config.BotApproachTimeout,
	}
	cancelPath(bot)
	return true
end

local function followRecovery(bot, humanoid, root, goal, now, sky)
	local recovery = bot.Recovery
	if not recovery then
		return false
	end
	local candidate = recovery.Candidates[recovery.Index]
	local footY = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
	local reached = horizontal(root.Position - candidate.Position).Magnitude <= Config.BotApproachReach
		and math.abs(footY - candidate.Position.Y) <= Config.BotWaypointReach
	local landed = recovery.Jumping and humanoid.FloorMaterial ~= Enum.Material.Air
		and footY >= candidate.Landing.Y - Config.BotApproachReach
		and horizontal(root.Position - candidate.Landing).Magnitude <= Config.BotWaypointReach
	if landed or (goal - recovery.Goal).Magnitude >= Config.BotRepathGoalShift then
		bot.Recovery = nil
		if landed then
			bot.ApproachAttempts = nil
		end
	elseif now >= recovery.Deadline or (reached and not candidate.Landing) then
		if recovery.Attempts then
			recovery.Attempts.Failed[candidate.Index] = true
		end
		cancelPath(bot)
		recovery.Index += 1
		candidate = recovery.Candidates[recovery.Index]
		if candidate then
			recovery.Deadline = now + Config.BotApproachTimeout
			recovery.Jumping = false
			recovery.PathStarted = false
		else
			if recovery.Attempts then
				recovery.Attempts.Exhausted = true
			end
			bot.Recovery = nil
		end
	elseif reached and not recovery.Jumping and humanoid.FloorMaterial ~= Enum.Material.Air then
		recovery.Jumping = true
		recovery.Deadline = now + Config.BotApproachJumpTime
		humanoid.Jump = true
	end
	if not bot.Recovery then
		cancelPath(bot)
		bot.NextRepathAt = nil
		clearProgress(bot)
		return false
	end
	if recovery.Jumping then
		moveTo(humanoid, candidate.Landing)
	else
		if candidate.Landing and not recovery.PathStarted then
			recovery.PathStarted = requestPath(bot, root.Position, candidate.Position, nil, goal, candidate)
		end
		local result = bot.PathResult
		if result then
			bot.PathResult = nil
			if result.Candidate == candidate
				and (goal - result.Goal).Magnitude < Config.BotRepathGoalShift then
				bot.Waypoints = result.Waypoints
				bot.WaypointIndex = 1
			end
		end
		followWaypoints(bot, humanoid, root, candidate.Position, sky)
	end
	return true
end

local function followPath(bot, humanoid, root, goal, actualGoal, reason, now, query, zoneCenter, zoneRadius)
	local sky = MapBuilder.CurrentMap == "Sky"
	local skyPlatform = sky and MapBuilder.GetNearestSkyPlatform(goal)
	local rootPlatform = sky and MapBuilder.GetNearestSkyPlatform(root.Position)
	local canRecover = not sky or (skyPlatform and skyPlatform == rootPlatform)
	local elevated = reason == "chase" and actualGoal.Y - root.Position.Y >= Config.BotElevatedThreshold
	if followRecovery(bot, humanoid, root, actualGoal, now, sky) then
		return
	end
	local stalled = reason ~= "idle" and BotManager.UpdateProgress(bot, root.Position, actualGoal, now)
	if stalled then
		clearProgress(bot)
		local recovered = elevated and canRecover
			and startRecovery(bot, humanoid, root, actualGoal, true, now, query, zoneCenter, zoneRadius)
		if not recovered and not elevated and not sky then
			recovered = startRecovery(bot, humanoid, root, actualGoal, false, now, query, zoneCenter, zoneRadius)
		end
		if recovered then
			followRecovery(bot, humanoid, root, actualGoal, now, sky)
			return
		end
	end

	if bot.PathComputing and bot.PathGoal and (goal - bot.PathGoal).Magnitude >= Config.BotRepathGoalShift then
		-- いったん変更された目標への結果は、目標が元の位置へ戻っても採用しない。
		bot.PathGeneration = (bot.PathGeneration or 0) + 1
		bot.PathGoal = nil
		bot.NextRepathAt = nil
	end
	local need = bot.NextRepathAt == nil or now >= bot.NextRepathAt
		or (bot.PathGoal and now >= bot.RepathAllowedAt and (bot.GoalChanged
			or (goal - bot.PathGoal).Magnitude >= Config.BotRepathGoalShift))
	if need and not bot.PathComputing and not bot.PathResult then
		local target = goal
		if skyPlatform and reason ~= "chase" and reason ~= "item" then
			local top = skyPlatform.Position.Y + skyPlatform.Size.Y / 2
			target = Vector3.new(goal.X, top, goal.Z)
			if math.abs(goal.X - skyPlatform.Position.X) > skyPlatform.Size.X / 2 - 2
				or math.abs(goal.Z - skyPlatform.Position.Z) > skyPlatform.Size.Z / 2 - 2 then
				target = Vector3.new(skyPlatform.Position.X, top, skyPlatform.Position.Z)
			end
		end
		local fallback = reason == "chase" and (target - actualGoal).Magnitude > 0 and actualGoal or nil
		requestPath(bot, root.Position, target, fallback, goal)
		bot.PathGoal = goal
		bot.NextRepathAt = now + roundRepathInterval
		bot.RepathAllowedAt = now + Config.BotRepathMinInterval
		bot.GoalChanged = false
	end
	local result = bot.PathResult
	if result then
		bot.PathResult = nil
		if not result.Candidate and (goal - result.Goal).Magnitude < Config.BotRepathGoalShift then
			bot.Waypoints = result.Waypoints
			bot.WaypointIndex = 1
			bot.PathTarget = result.Target
			bot.PathUsesActualGoal = result.UsesFallback
			if not bot.Waypoints then
				if elevated and canRecover
					and startRecovery(bot, humanoid, root, actualGoal, true, now, query, zoneCenter, zoneRadius) then
					followRecovery(bot, humanoid, root, actualGoal, now, sky)
					return
				end
				if sky then
					bot.PathTarget = rootPlatform and (rootPlatform.Position + Vector3.new(0, rootPlatform.Size.Y / 2, 0))
						or root.Position
				end
			end
		else
			bot.NextRepathAt = nil
		end
	end
	local target = sky and (bot.PathTarget or root.Position) or (bot.PathUsesActualGoal and actualGoal or goal)
	followWaypoints(bot, humanoid, root, target, sky)
end

local function considerItems(bot, threat)
	local data = GameState.GetData(bot)
	if #data.HeldItems == 0 then
		return
	end
	local taggerRole = GameState.IsTagger(bot)
	local order = { "Shield", "Star", "Warp", "Dash", "Banana" }
	for _, want in ipairs(order) do
		for slot, itemId in ipairs(data.HeldItems) do
			if itemId == want then
				local skip = false
				if itemId == "Dash" and GameState.IsDashing(bot) then
					skip = true
				elseif itemId == "Shield" and GameState.HasShield(bot) then
					skip = true
				elseif itemId == "Star" and GameState.HasStar(bot) then
					skip = true
				end
				local def = Config.GetItem(itemId)
				if not skip and def and (not taggerRole or def.CanTaggerUse) and BotManager.ShouldUseItem(itemId, taggerRole, threat) then
					ItemManager.TryUse(bot, slot)
					return
				end
			end
		end
	end
end

local function perceivedPosition(player, now)
	local data = GameState.GetData(player)
	if (data.BeastDecoyUntil or 0) > now then
		return data.BeastDecoyPosition
	end
	if data.BeastUsed == "Amun" and data.BeastVisibility and data.BeastVisibility.Until > now then
		return nil
	end
	local root = GameState.GetRootPart(player)
	return root and root.Position, root and root.AssemblyLinearVelocity
end

local function think(bot, now)
	local root = GameState.GetRootPart(bot)
	local humanoid = GameState.GetHumanoid(bot)
	if not root or not root.Position or not humanoid or GameState.IsStunned(bot) or GameState.IsDowned(bot)
		or GameState.GetData(bot).FrozenUntil > now then
		bot.LastThink = nil
		if bot.Recovery then
			cancelPath(bot)
			bot.Recovery = nil
			bot.NextRepathAt = nil
		end
		clearProgress(bot)
		return
	end
	if bot.LastThink and now - bot.LastThink < Config.BotDecisionInterval then
		return
	end
	local pos = root.Position
	if type(root.SetNetworkOwner) == "function" and (bot.NextOwnAt == nil or now >= bot.NextOwnAt) then
		bot.NextOwnAt = now + 1
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end

	local dt = 0
	if bot.LastThink then
		dt = now - bot.LastThink
		if dt < 0 then
			dt = 0
		elseif dt > 1 then
			dt = 1
		end
	end
	bot.LastThink = now

	local moved = 0
	if bot.LastX ~= nil then
		local dx = pos.X - bot.LastX
		local dy = pos.Y - bot.LastY
		local dz = pos.Z - bot.LastZ
		moved = math.sqrt(dx * dx + dy * dy + dz * dz)
	end
	local shouldJump = false
	if bot.LastX ~= nil then
		bot.StuckTime, shouldJump = BotManager.UpdateStuck(bot.StuckTime, moved, dt)
	end
	bot.LastX = pos.X
	bot.LastY = pos.Y
	bot.LastZ = pos.Z

	local blindUntil = math.max(tonumber(bot.BlindUntil) or 0, tonumber(GameState.GetData(bot).BlindUntil) or 0)
	local blind = blindUntil > now
	if blind then
		if bot.BlindAngle == nil then
			bot.BlindAngle = math.random() * math.pi * 2
		end
	else
		bot.BlindAngle = nil
	end

	local runners = {}
	local taggerX, taggerZ = nil, nil
	local role = GameState.Taggers[bot]
	local threat = math.huge
	if not role then
		for tagger in pairs(GameState.Taggers) do
			local position = GameState.IsAlive(tagger) and perceivedPosition(tagger, now)
			if position then
				local distance = (pos - position).Magnitude
				if distance < threat then
					threat = distance
					taggerX, taggerZ = position.X, position.Z
				end
			end
		end
	end
	if role and not blind then
		for _, other in ipairs(GameState.ParticipantList()) do
			-- タッチ返しできない相手は追いかけない
			if not GameState.IsTagger(other) and other ~= role.NoTagBack and GameState.IsAlive(other) then
				local position, velocity = perceivedPosition(other, now)
				if position then
					table.insert(runners, {
						X = position.X, Y = position.Y, Z = position.Z,
						Position = position, Velocity = velocity, Player = other,
					})
				end
			end
		end
	end

	local boxes = {}
	if not role then
		for _, position in ipairs(ItemManager.GetActiveBoxPositions()) do
			table.insert(boxes, { X = position.X, Z = position.Z, Position = position })
		end
	end

	local zoneActive = ZoneManager.IsActive()
	local center = ZoneManager.GetCenter()
	local radius = ZoneManager.GetRadius()
	local gx, gz, reason, subject = BotManager.ChooseGoal({
		Role = GameState.IsTagger(bot) and "Tagger" or "Runner",
		X = pos.X,
		Y = pos.Y,
		Z = pos.Z,
		TaggerX = taggerX,
		TaggerZ = taggerZ,
		Runners = runners,
		Boxes = boxes,
		ZoneActive = zoneActive,
		ZoneX = center and center.X or 0,
		ZoneZ = center and center.Z or 0,
		ZoneRadius = radius,
		ZoneShrunk = ZoneManager.IsShrunk(),
		Blind = blind,
		BlindAngle = bot.BlindAngle,
	})

	local actualGoal = subject and subject.Position or Vector3.new(gx, pos.Y, gz)
	local targetPlayer = subject and subject.Player
	if reason ~= bot.GoalReason or targetPlayer ~= bot.GoalPlayer then
		if bot.GoalReason then
			bot.NextRepathAt = nil
		end
		bot.GoalReason, bot.GoalPlayer = reason, targetPlayer
		bot.GoalChanged = true
		bot.PathGoal = nil
		bot.Recovery = nil
		bot.ApproachAttempts = nil
		bot.PathTarget = nil
		bot.PathUsesActualGoal = false
		cancelPath(bot)
		clearProgress(bot)
	end
	if reason == "chase" then
		threat = (pos - actualGoal).Magnitude
	end
	considerItems(bot, threat)
	if reason == "idle" then
		moveTo(humanoid, root.Position)
		return
	end
	local query = navigationQuery(bot)
	local goal = actualGoal
	if reason == "chase" then
		local predicted = BotManager.PredictPosition(actualGoal, subject.Velocity)
		local offset = predicted - actualGoal
		if offset.Magnitude > 0 and not workspace:Raycast(actualGoal, offset, query) then
			if actualGoal.Y - pos.Y < Config.BotElevatedThreshold then
				goal = predicted
			else
				local currentGround = groundAt(actualGoal, query)
				local predictedGround = groundAt(predicted, query)
				if currentGround and predictedGround
					and math.abs(predictedGround.Y - currentGround.Y) < Config.BotElevatedThreshold then
					goal = predicted
				end
			end
		end
	elseif not subject and MapBuilder.CurrentMap ~= "Sky" then
		local ground = groundAt(actualGoal + Vector3.new(0, Config.BotApproachProbeHeight, 0), query)
		goal = ground or actualGoal
		actualGoal = goal
	end
	followPath(bot, humanoid, root, goal, actualGoal, reason, now, query, zoneActive and not role and center, radius)
	if shouldJump and not bot.Recovery then
		humanoid.Jump = true
	end
end

---------------------------------------------------------------------
-- ラウンドからの呼び出し
---------------------------------------------------------------------

function BotManager.GetActive()
	local copy = {}
	for index, bot in ipairs(activeBots) do
		copy[index] = bot
	end
	return copy
end

function BotManager.ActiveCount()
	return #activeBots
end

-- 歩かせるのをやめる（結果表示のあいだ、その場に止める）
function BotManager.Halt()
	for _, bot in ipairs(activeBots) do
		cancelPath(bot)
		local humanoid = GameState.GetHumanoid(bot)
		if humanoid then
			humanoid.WalkSpeed = 0
			local root = GameState.GetRootPart(bot)
			if root and root.Position then
				moveTo(humanoid, root.Position)
			end
		end
	end
end

-- ボットを全員消す。サーバーに残さない。
function BotManager.DespawnAll()
	local bots = activeBots
	activeBots = {}
	for _, bot in ipairs(bots) do
		GameState.UnregisterCharacter(bot.Character)
		TaggerLook.Clear(bot)
		DeckManager.Release(bot)
		GameState.Participants[bot] = nil
		GameState.Taggers[bot] = nil
		GameState.ClearData(bot)
		bot.Parent = nil
		if bot.Character then
			bot.Character:Destroy()
			bot.Character = nil
		end
	end
	local folder = workspace:FindFirstChild("Bots")
	if folder then
		folder:Destroy()
	end
end

-- humans は今ラウンドの人間の配列。目標までの差分だけスポーンする。
function BotManager.Fill(humans)
	local list = humans or {}
	local count = BotManager.CountToSpawn(#list)
	local speed, interval = BotManager.StrengthForTierIndex(1)
	if count > 0 then
		local indices = {}
		for _, player in ipairs(list) do
			local record = RankManager.Get(player)
			table.insert(indices, BotManager.TierIndexForRP(record and record.RP))
		end
		speed, interval = BotManager.StrengthForTierIndex(BotManager.AverageTierIndex(indices))
	end

	BotManager.DespawnAll()
	roundRepathInterval = interval
	if count <= 0 then
		return {}
	end

	local platforms = MapBuilder.GetSkyPlatforms()
	local spawnPart = platforms and platforms:FindFirstChild("ArenaStart") or findSpawnPart()
	for index = 1, count do
		local bot = createBot(index, count, spawnPart)
		bot.SpeedMultiplier = speed
		bot.NextRepathAt = GameState.Now() + (index - 1) * 0.12
		GameState.Participants[bot] = true
		GameState.ResetData(bot)
		GameState.RefreshSpeed(bot)
		table.insert(activeBots, bot)
	end
	return BotManager.GetActive()
end

-- ひとりモード用：count 体を出す。opts.SoloCap = true なら人より少し遅くする
function BotManager.Spawn(count, opts)
	BotManager.DespawnAll()
	roundRepathInterval = Config.BotSoloRepathInterval
	local spawnPart = findSpawnPart()
	for index = 1, count do
		local bot = createBot(index, count, spawnPart)
		bot.SoloCap = opts and opts.SoloCap or nil
		bot.NextRepathAt = GameState.Now() + (index - 1) * 0.12
		GameState.Participants[bot] = true
		GameState.ResetData(bot)
		GameState.RefreshSpeed(bot)
		table.insert(activeBots, bot)
	end
	return BotManager.GetActive()
end

function BotManager.IsBot(player)
	return type(player) == "table" and player.IsBot == true
end

BotManager.List = BotManager.GetActive
BotManager.Clear = BotManager.DespawnAll

-- サーバー所有のボットは、人間と同じ式で毎フレーム氷上の慣性を更新する。
game:GetService("RunService").Heartbeat:Connect(function(dt)
	if GameState.Phase ~= "Round" or MapBuilder.CurrentMap ~= "Ice" then
		return
	end
	for _, bot in ipairs(activeBots) do
		local humanoid = GameState.GetHumanoid(bot)
		local root = GameState.GetRootPart(bot)
		local data = GameState.GetData(bot)
		local stunSequence = bot.Character:GetAttribute("StunSequence")
		if bot.IceStunSequence ~= stunSequence then
			bot.IceStunSequence = stunSequence
			bot.IceVelocity = nil
		end
		if root and not root.Anchored and humanoid and GameState.IsAlive(bot) and GameState.IsParticipant(bot)
			and not GameState.IsStunned(bot)
			and data.SpikeBootsUntil <= GameState.Now() and not GameState.IsDowned(bot) then
			local actual = root.AssemblyLinearVelocity
			local knockback = root:GetAttribute("BeastKnockback")
			if bot.IceKnockback ~= knockback then
				bot.IceVelocity = nil
				bot.IceKnockback = knockback
			end
			local previous = bot.IceVelocity or Vector3.new(actual.X, 0, actual.Z)
			bot.IceVelocity = Config.IceVelocity(previous, humanoid.MoveDirection, humanoid.WalkSpeed, dt)
			root.AssemblyLinearVelocity = Vector3.new(bot.IceVelocity.X, actual.Y, bot.IceVelocity.Z)
		else
			bot.IceVelocity = nil
		end
	end
end)

function BotManager.Tick()
	if #activeBots == 0 or GameState.Phase ~= "Round" then
		return
	end
	local now = GameState.Now()
	for _, bot in ipairs(activeBots) do
		if GameState.IsParticipant(bot) and GameState.IsAlive(bot) then
			think(bot, now)
		end
	end
end

return BotManager
