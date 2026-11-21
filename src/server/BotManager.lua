-- BotManager: 人数が足りないラウンドをボット（NPC）で補う
-- ボットは Player ではなく { IsBot = true, ... } のテーブル。GameState の辞書キーに使う。
-- 強さは人間の平均段位から表を引くだけ（機械学習ではない）。
-- 経路は PathfindingService。失敗したときと、サービスが無いときは MoveTo の直進に倒す。

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
local roundRepathInterval = 1.4

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
	if type(distance) ~= "number" then
		return false
	end
	if itemId == "Dash" then
		return isTagger ~= true and distance <= Config.BotDashDistance
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

local function inwardPoint(x, z, zx, zz, radius)
	local dx = x - zx
	local dz = z - zz
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < 0.001 then
		return zx, zz
	end
	local desired = radius * 0.55
	if dist <= desired then
		return x, z
	end
	return zx + dx / dist * desired, zz + dz / dist * desired
end

-- 次の目標（XZ だけ）。戻り値: goalX, goalZ, 理由（"zone" / "blind" / "chase" / "item" / "flee" / "idle"）
function BotManager.ChooseGoal(ctx)
	local x = ctx.X or 0
	local z = ctx.Z or 0
	local zoneActive = ctx.ZoneActive == true
	local radius = ctx.ZoneRadius or 0
	local zx = ctx.ZoneX or 0
	local zz = ctx.ZoneZ or 0

	if zoneActive and ctx.Role ~= "Tagger" and radius > 0 then
		local dx = x - zx
		local dz = z - zz
		local dist = math.sqrt(dx * dx + dz * dz)
		local edge = radius * (Config.BotZoneEdgeRatio or 0.85)
		if dist > edge then
			local gx, gz = inwardPoint(x, z, zx, zz, radius)
			return gx, gz, "zone"
		end
	end

	if ctx.Blind then
		local angle = ctx.BlindAngle or 0
		local reach = Config.BotFleeDistance or 28
		local gx = x + math.cos(angle) * reach
		local gz = z + math.sin(angle) * reach
		if zoneActive and radius > 0 then
			gx, gz = clampInside(gx, gz, zx, zz, radius * (Config.BotZoneEdgeRatio or 0.85))
		end
		return gx, gz, "blind"
	end

	if ctx.Role == "Tagger" then
		local nearest = nil
		local best = math.huge
		for _, runner in ipairs(ctx.Runners or {}) do
			local dx = (runner.X or 0) - x
			local dz = (runner.Z or 0) - z
			local d2 = dx * dx + dz * dz
			if d2 < best then
				best = d2
				nearest = runner
			end
		end
		if nearest then
			return nearest.X or x, nearest.Z or z, "chase"
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
			return nearest.X or x, nearest.Z or z, "item"
		end
	end

	if taggerDist ~= nil and taggerDist > 0.05 then
		local dx = x - ctx.TaggerX
		local dz = z - ctx.TaggerZ
		local reach = Config.BotFleeDistance or 28
		local gx = x + dx / taggerDist * reach
		local gz = z + dz / taggerDist * reach
		if zoneActive and radius > 0 then
			gx, gz = clampInside(gx, gz, zx, zz, radius * (Config.BotZoneEdgeRatio or 0.85))
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

local function createBot(index, total, spawnPart)
	local name = "ボット" .. tostring(index)
	local x, y, z = standPosition(index, total, spawnPart)
	local character = buildCharacter(name, x, y, z)
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

local function followPath(bot, humanoid, root, goal, now)
	local sky = MapBuilder.CurrentMap == "Sky"
	local need = bot.NextRepathAt == nil or now >= bot.NextRepathAt
		or (not sky and bot.Waypoints == nil)
	if need then
		local target = goal
		if sky then
			local platform = MapBuilder.GetNearestSkyPlatform(goal)
			if platform then
				local top = platform.Position.Y + platform.Size.Y / 2
				target = Vector3.new(goal.X, top, goal.Z)
				if math.abs(goal.X - platform.Position.X) > platform.Size.X / 2 - 2
					or math.abs(goal.Z - platform.Position.Z) > platform.Size.Z / 2 - 2 then
					target = Vector3.new(platform.Position.X, top, platform.Position.Z)
				end
			end
		end
		bot.PathTarget = target
		bot.Waypoints = computePath(root.Position, target)
		if sky and not bot.Waypoints then
			local nearest = MapBuilder.GetNearestSkyPlatform(root.Position)
			bot.PathTarget = nearest and (nearest.Position + Vector3.new(0, nearest.Size.Y / 2, 0))
				or root.Position
		end
		bot.WaypointIndex = 1
		bot.NextRepathAt = now + roundRepathInterval
	end

	local target = sky and (bot.PathTarget or root.Position) or goal
	local waypoints = bot.Waypoints
	if waypoints then
		local index = bot.WaypointIndex or 1
		local reach = Config.BotWaypointReach or 3.5
		while waypoints[index] do
			local wp = waypoints[index]
			local wpPos = wp.Position
			if not wpPos then
				index = index + 1
			else
				local dx = root.Position.X - wpPos.X
				local dy = root.Position.Y - wpPos.Y
				local dz = root.Position.Z - wpPos.Z
				local dist = math.sqrt(dx * dx + dz * dz + (sky and 0 or dy * dy))
				if dist <= reach then
					if wp.Action == Enum.PathWaypointAction.Jump then
						humanoid.Jump = true
					end
					index = index + 1
				else
					target = wpPos
					break
				end
			end
		end
		bot.WaypointIndex = index
		if waypoints[index] == nil then
			bot.Waypoints = nil
			target = sky and bot.PathTarget or goal
		end
	end
	moveTo(humanoid, target)
end

local function distance3(a, b)
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function threatDistance(bot, pos)
	if GameState.IsTagger(bot) then
		local best = math.huge
		for _, other in ipairs(GameState.ParticipantList()) do
			if other ~= bot and GameState.IsAlive(other) then
				local otherRoot = GameState.GetRootPart(other)
				if otherRoot and otherRoot.Position then
					local dist = distance3(pos, otherRoot.Position)
					if dist < best then
						best = dist
					end
				end
			end
		end
		return best
	end
	local tagger = GameState.Tagger
	if not tagger or tagger == bot then
		return math.huge
	end
	local taggerRoot = GameState.GetRootPart(tagger)
	if not taggerRoot or not taggerRoot.Position then
		return math.huge
	end
	return distance3(pos, taggerRoot.Position)
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

local function think(bot, now)
	local root = GameState.GetRootPart(bot)
	local humanoid = GameState.GetHumanoid(bot)
	if not root or not root.Position or not humanoid or GameState.IsStunned(bot) then
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
	local tagger = GameState.Tagger
	if tagger and tagger ~= bot then
		local taggerRoot = GameState.GetRootPart(tagger)
		if taggerRoot and taggerRoot.Position then
			taggerX = taggerRoot.Position.X
			taggerZ = taggerRoot.Position.Z
		end
	end
	for _, other in ipairs(GameState.ParticipantList()) do
		-- タッチ返しできない相手は追いかけない
		if other ~= bot and other ~= tagger and other ~= GameState.NoTagBack and GameState.IsAlive(other) then
			local otherRoot = GameState.GetRootPart(other)
			if otherRoot and otherRoot.Position then
				table.insert(runners, { X = otherRoot.Position.X, Z = otherRoot.Position.Z })
			end
		end
	end

	local boxes = {}
	for _, position in ipairs(ItemManager.GetActiveBoxPositions()) do
		table.insert(boxes, { X = position.X, Z = position.Z })
	end

	local zoneActive = ZoneManager.IsActive()
	local center = ZoneManager.GetCenter()
	local gx, gz = BotManager.ChooseGoal({
		Role = GameState.IsTagger(bot) and "Tagger" or "Runner",
		X = pos.X,
		Z = pos.Z,
		TaggerX = taggerX,
		TaggerZ = taggerZ,
		Runners = runners,
		Boxes = boxes,
		ZoneActive = zoneActive,
		ZoneX = center and center.X or 0,
		ZoneZ = center and center.Z or 0,
		ZoneRadius = ZoneManager.GetRadius(),
		Blind = blind,
		BlindAngle = bot.BlindAngle,
	})

	considerItems(bot, threatDistance(bot, pos))
	followPath(bot, humanoid, root, Vector3.new(gx, pos.Y, gz), now)
	if shouldJump then
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
		bot.Waypoints = nil
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
		GameState.BeenTagger[bot] = nil
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
	local speed, interval = 1, 1.4
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
	roundRepathInterval = 1.0
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
		if root and humanoid and GameState.IsAlive(bot) and GameState.IsParticipant(bot)
			and data.SpikeBootsUntil <= GameState.Now() and not GameState.IsSlipping(bot) then
			local actual = root.AssemblyLinearVelocity
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
