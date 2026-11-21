-- 鬼スキルの受付と、鬼の間だけ有効な効果の管理。
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GameState = require(script.Parent:WaitForChild("GameState"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local TaggerSkills = {}
local skills = Config.TaggerSkills

function TaggerSkills.IsReady(readyAt, now)
	return readyAt == nil or now >= readyAt
end

function TaggerSkills.CatchBoostEnd(previous, now, window)
	if previous and now >= previous and now - previous <= window then
		return now + skills.CatchStreak.Duration
	end
	return nil
end

function TaggerSkills.RecordCatch(player, now)
	local data = GameState.GetData(player)
	local untilTime = TaggerSkills.CatchBoostEnd(data.LastCatchAt, now, skills.CatchStreak.Window)
	data.LastCatchAt = now
	if untilTime then
		data.CatchBoostUntil = untilTime
		GameState.RefreshSpeed(player)
	end
end

local function sendUpdate(player, data, smell)
	if Remotes.IsRealPlayer(player) then
		Remotes.TaggerSkillUpdate:FireClient(player, { ReadyAt = data.TaggerSkillReadyAt, Smell = smell })
	end
end

function TaggerSkills.ResetRoleEffects(player)
	local data = GameState.GetData(player)
	table.clear(data.TaggerSkillReadyAt)
	data.TaggerDashUntil = 0
	data.CatchBoostUntil = 0
	data.TaggerSmellUntil = 0
	data.NextSmellUpdate = 0
	sendUpdate(player, data)
end

local function runnerRoot(player)
	if GameState.IsParticipant(player) and not GameState.IsTagger(player) and GameState.IsAlive(player) then
		return GameState.GetRootPart(player)
	end
	return nil
end

function TaggerSkills.RoarTargets(position)
	local targets = {}
	for player in pairs(GameState.Participants) do
		local root = runnerRoot(player)
		if root and (root.Position - position).Magnitude <= skills.Roar.Radius and not GameState.HasStar(player) then
			table.insert(targets, player)
		end
	end
	return targets
end

local function updateSmell(player, data, now)
	data.NextSmellUpdate = now + skills.Smell.UpdateInterval
	local source = GameState.GetRootPart(player)
	local position, best = nil, math.huge
	if source then
		for runner in pairs(GameState.Participants) do
			local root = runnerRoot(runner)
			if root then
				local distance = (root.Position - source.Position).Magnitude
				if distance < best then
					position, best = root.Position, distance
				end
			end
		end
	end
	local smell = position and {
		Position = position,
		Distance = best,
		ExpiresAt = workspace:GetServerTimeNow() + data.TaggerSmellUntil - now,
	}
	sendUpdate(player, data, smell)
end

function TaggerSkills.Use(player, id)
	if (id ~= "Dash" and id ~= "Roar" and id ~= "Smell") or GameState.Phase ~= "Round"
		or not GameState.IsTagger(player) or not GameState.IsParticipant(player) or not GameState.IsAlive(player) then
		return
	end
	local data = GameState.GetData(player)
	local now = GameState.Now()
	local serverTime = workspace:GetServerTimeNow()
	local root = GameState.GetRootPart(player)
	if not root or data.FrozenUntil > now or GameState.IsDowned(player)
		or GameState.IsProne(player) or GameState.IsStunned(player)
		or not TaggerSkills.IsReady(data.TaggerSkillReadyAt[id], serverTime) then
		return
	end

	local def = skills[id]
	data.TaggerSkillReadyAt[id] = serverTime + def.Cooldown
	if id == "Dash" then
		data.TaggerDashUntil = now + def.Duration
		GameState.RefreshSpeed(player)
	elseif id == "Roar" then
		for _, target in ipairs(TaggerSkills.RoarTargets(root.Position)) do
			GameState.ApplySlow(target, "Roar")
		end
	else
		data.TaggerSmellUntil = now + def.Duration
	end
	if data.TaggerSmellUntil > now then
		updateSmell(player, data, now)
	else
		sendUpdate(player, data)
	end
end

function TaggerSkills.Tick(now)
	for player in pairs(GameState.Taggers) do
		local data = GameState.GetData(player)
		local dashEnded = data.TaggerDashUntil > 0 and data.TaggerDashUntil <= now
		local catchEnded = data.CatchBoostUntil > 0 and data.CatchBoostUntil <= now
		if dashEnded or catchEnded then
			if dashEnded then
				data.TaggerDashUntil = 0
			end
			if catchEnded then
				data.CatchBoostUntil = 0
			end
			GameState.RefreshSpeed(player)
		end
		if data.TaggerSmellUntil > 0 then
			if data.TaggerSmellUntil <= now or not GameState.IsParticipant(player) or not GameState.IsAlive(player) then
				data.TaggerSmellUntil = 0
				sendUpdate(player, data)
			elseif now >= data.NextSmellUpdate then
				updateSmell(player, data, now)
			end
		end
	end
end

function TaggerSkills.Init()
	Remotes.UseTaggerSkill.OnServerEvent:Connect(TaggerSkills.Use)
	RunService.Heartbeat:Connect(function()
		if GameState.Phase == "Round" then
			TaggerSkills.Tick(GameState.Now())
		end
	end)
end

return TaggerSkills
