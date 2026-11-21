-- 氷の床で、入力の変化に合わせて水平速度を徐々に変える。
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
	if not participant or workspace:GetAttribute("CurrentGimmick") ~= "Ice"
		or not root or not humanoid or humanoid.Health <= 0
		or character:GetAttribute("BananaSlipping") or bootsUntil > workspace:GetServerTimeNow() then
		previous = nil
		return
	end

	local actual = root.AssemblyLinearVelocity
	if lastRoot ~= root then
		previous = nil
		lastRoot = root
	end
	local horizontal = previous or Vector3.new(actual.X, 0, actual.Z)
	previous = Config.IceVelocity(horizontal, humanoid.MoveDirection, humanoid.WalkSpeed, dt)
	root.AssemblyLinearVelocity = Vector3.new(previous.X, actual.Y, previous.Z)
end)
