-- 氷上の慣性と、クライアントが操作するキャラクターの転倒姿勢を処理する。
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local participant = false
local bootsUntil = 0
local previous
local lastRoot
local lastKnockback
local lastStun
local fallenHumanoid

remotes:WaitForChild("StateUpdate").OnClientEvent:Connect(function(state)
	participant = state.Phase == "Round" and table.find(state.Participants, player.UserId) ~= nil
	if not participant then
		previous = nil
		bootsUntil = 0
	end
end)

remotes:WaitForChild("ItemUpdate").OnClientEvent:Connect(function(state)
	bootsUntil = state.SpikeBootsUntil or 0
	if bootsUntil > workspace:GetServerTimeNow() then
		previous = nil
	end
end)

RunService.PostSimulation:Connect(function(dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local downed = humanoid and character:GetAttribute("BananaDowned") == true
	if fallenHumanoid and (fallenHumanoid ~= humanoid or not downed) then
		local states = Enum.HumanoidStateType
		fallenHumanoid:SetStateEnabled(states.GettingUp, true)
		if fallenHumanoid.Health > 0 and fallenHumanoid:GetState() == states.FallingDown then
			fallenHumanoid:ChangeState(states.GettingUp)
		end
		fallenHumanoid = nil
	end
	if downed and root and humanoid.Health > 0 then
		if fallenHumanoid ~= humanoid then
			local states = Enum.HumanoidStateType
			humanoid:SetStateEnabled(states.GettingUp, false)
			humanoid:ChangeState(states.FallingDown)
			fallenHumanoid = humanoid
		end
		humanoid.Jump = false
		root.AssemblyLinearVelocity = Vector3.new(0, math.min(0, root.AssemblyLinearVelocity.Y), 0)
		previous = nil
		return
	end
	local stun = character and character:GetAttribute("StunUntil")
	local stunSequence = character and character:GetAttribute("StunSequence")
	if lastStun ~= stunSequence then
		lastStun = stunSequence
		previous = nil
	end
	if stun and stun > workspace:GetServerTimeNow() then
		previous = nil
		return
	end
	local glide = character and character:GetAttribute("BeastGlideVelocity")
	if glide and root and humanoid and humanoid.Health > 0 then
		local velocity = root.AssemblyLinearVelocity
		if humanoid.FloorMaterial == Enum.Material.Air and velocity.Y < 0 then
			root.AssemblyLinearVelocity = glide + Vector3.new(0, math.max(velocity.Y, -Config.Beasts.Nut.FallSpeed), 0)
		end
		previous = nil
		return
	end
	local onIce = workspace:GetAttribute("CurrentGimmick") == "Ice"
		or (character and character:GetAttribute("IcePatch"))
	if not participant or not onIce
		or not root or root.Anchored or not humanoid or humanoid.Health <= 0
		or character:GetAttribute("Grappling") or bootsUntil > workspace:GetServerTimeNow() then
		previous = nil
		return
	end

	local actual = root.AssemblyLinearVelocity
	local knockback = root:GetAttribute("BeastKnockback")
	if lastRoot ~= root or lastKnockback ~= knockback then
		previous = nil
		lastRoot = root
		lastKnockback = knockback
	end
	local horizontal = previous or Vector3.new(actual.X, 0, actual.Z)
	previous = Config.IceVelocity(horizontal, humanoid.MoveDirection, humanoid.WalkSpeed, dt)
	root.AssemblyLinearVelocity = Vector3.new(previous.X, actual.Y, previous.Z)
end)
