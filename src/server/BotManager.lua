-- BotManager: ひとりモード用のボット（コンピューターのプレイヤー）
--
-- ボットは Player ではないが、試合の処理からは「プレイヤーと同じ形の表」に見えるようにする。
--   { IsBot = true, Name, DisplayName, UserId（マイナスの数）, Character（Model）, Parent = Players }
-- 動き:
--   鬼のとき   … いちばん近い相手を追いかける（反応は少し遅め）
--   逃げるとき … 鬼が近ければ反対側へ、遠ければエリアの中をうろうろ。エリアの外には出ない

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GameState = require(script.Parent:WaitForChild("GameState"))
local ZoneManager = require(script.Parent:WaitForChild("ZoneManager"))

local BotManager = {}

local bots = {}          -- ボットの表の配列
local thinkAt = {}       -- [bot] = 次に行き先を決め直す時刻
local wanderTarget = {}  -- [bot] = うろうろの行き先

local BOT_COLORS = {
	Color3.fromRGB(255, 120, 120), Color3.fromRGB(120, 180, 255), Color3.fromRGB(255, 210, 90),
	Color3.fromRGB(140, 220, 140), Color3.fromRGB(210, 150, 255), Color3.fromRGB(255, 160, 210),
	Color3.fromRGB(120, 230, 220),
}

function BotManager.IsBot(player)
	return type(player) == "table" and player.IsBot == true
end

local function makeModel(index)
	local description = Instance.new("HumanoidDescription")
	local color = BOT_COLORS[(index - 1) % #BOT_COLORS + 1]
	description.HeadColor = Color3.fromRGB(255, 220, 180)
	description.TorsoColor = color
	description.LeftArmColor = color
	description.RightArmColor = color
	description.LeftLegColor = Color3.fromRGB(60, 60, 80)
	description.RightLegColor = Color3.fromRGB(60, 60, 80)
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	model.Name = "Bot" .. index
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = "ボット" .. index
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	end
	return model
end

-- ボットを count 体つくって、中央のまわりに置く
function BotManager.Spawn(count)
	BotManager.Clear()
	for index = 1, count do
		local ok, model = pcall(makeModel, index)
		if ok and model then
			local angle = (index / count) * math.pi * 2
			model:PivotTo(CFrame.new(math.cos(angle) * 30, 5, math.sin(angle) * 30))
			model.Parent = workspace
			local root = model:FindFirstChild("HumanoidRootPart")
			if root then
				pcall(function()
					root:SetNetworkOwner(nil) -- 動きはサーバーが決める
				end)
			end
			table.insert(bots, {
				IsBot = true,
				Name = model.Name,
				DisplayName = "ボット" .. index,
				UserId = -index,
				Character = model,
				Parent = Players,
			})
		else
			warn("[BotManager] ボットを作れませんでした: " .. tostring(model))
		end
	end
	return bots
end

function BotManager.List()
	return bots
end

function BotManager.Clear()
	for _, bot in ipairs(bots) do
		if bot.Character then
			bot.Character:Destroy()
		end
		bot.Parent = nil
		GameState.ClearData(bot)
	end
	bots = {}
	thinkAt = {}
	wanderTarget = {}
end

---------------------------------------------------------------------
-- 動き
---------------------------------------------------------------------

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- 点をエリアの内側（半径の 80%）に収める
local function clampToZone(position)
	local center = ZoneManager.GetCenter()
	local radius = ZoneManager.GetRadius() * 0.8
	local offset = flat(position - center)
	if offset.Magnitude > radius and offset.Magnitude > 0 then
		offset = offset.Unit * radius
	end
	return Vector3.new(center.X + offset.X, position.Y, center.Z + offset.Z)
end

local function randomPointInZone()
	local center = ZoneManager.GetCenter()
	local radius = ZoneManager.GetRadius() * 0.7
	local angle = math.random() * math.pi * 2
	local dist = math.random() * radius
	return Vector3.new(center.X + math.cos(angle) * dist, center.Y, center.Z + math.sin(angle) * dist)
end

local function nearestTarget(bot, root)
	local best, bestDist = nil, math.huge
	for _, other in ipairs(GameState.ParticipantList()) do
		if other ~= bot and GameState.IsAlive(other) then
			local otherRoot = GameState.GetRootPart(other)
			if otherRoot then
				local dist = (otherRoot.Position - root.Position).Magnitude
				if dist < bestDist then
					best, bestDist = otherRoot, dist
				end
			end
		end
	end
	return best
end

local function think(bot, now)
	local humanoid = GameState.GetHumanoid(bot)
	local root = GameState.GetRootPart(bot)
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local data = GameState.GetData(bot)

	if GameState.IsTagger(bot) then
		if (data.BlindUntil or 0) > now then
			humanoid:MoveTo(root.Position) -- 目くらまし中は立ち止まる
			return
		end
		local target = nearestTarget(bot, root)
		if target then
			-- 相手の少し先をねらう
			local lead = flat(target.AssemblyLinearVelocity) * 0.3
			humanoid:MoveTo(target.Position + lead)
		end
		return
	end

	local taggerRoot = GameState.GetRootPart(GameState.Tagger)
	local destination
	if taggerRoot and (taggerRoot.Position - root.Position).Magnitude < Config.BotFleeDistance then
		local away = flat(root.Position - taggerRoot.Position)
		if away.Magnitude < 0.1 then
			away = Vector3.new(1, 0, 0)
		end
		-- 少し横にそれながら逃げる（まっすぐだと壁に追い込まれやすい）
		local side = Vector3.new(-away.Z, 0, away.X).Unit * (math.random() - 0.5) * 12
		destination = clampToZone(root.Position + away.Unit * 24 + side)
	else
		local current = wanderTarget[bot]
		if not current or flat(current - root.Position).Magnitude < 6 or math.random() < 0.08 then
			current = randomPointInZone()
			wanderTarget[bot] = current
		end
		destination = clampToZone(current)
	end
	humanoid:MoveTo(destination)

	-- ほとんど進んでいなければ跳んで段差を越える
	if flat(root.AssemblyLinearVelocity).Magnitude < 2 and math.random() < 0.5 then
		humanoid.Jump = true
	end
end

-- 試合中、RoundManager のループから呼ぶ
function BotManager.Tick()
	local now = GameState.Now()
	for _, bot in ipairs(bots) do
		if GameState.IsParticipant(bot) and (thinkAt[bot] or 0) <= now then
			thinkAt[bot] = now + Config.BotThinkInterval
			think(bot, now)
		end
	end
end

return BotManager
