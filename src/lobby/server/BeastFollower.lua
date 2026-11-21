-- ロビーにいる全員に見える、装備中の召喚獣を管理する。
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BeastModels = require(Shared:WaitForChild("BeastModels"))

local BeastFollower = {}
local settings = Config.LobbyBeastFollower
local followers = {}
local folder = Instance.new("Folder")
folder.Name = "LobbyBeastFollowers"
folder.Parent = workspace

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { workspace:WaitForChild("LobbyMap") }
groundParams.RespectCanCollide = true

function BeastFollower.GetTargetPosition(position, lookVector)
	local forward = Vector3.new(lookVector.X, 0, lookVector.Z)
	if forward.Magnitude < 0.001 then
		forward = Vector3.new(0, 0, -1)
	end
	forward = forward.Unit
	return position - forward * settings.FollowDistance, forward
end

local function clearModel(follower)
	if follower.model then
		follower.model:Destroy()
		follower.model = nil
	end
	follower.position = nil
end

local function step(follower, alpha, elapsed)
	local character = follower.character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		clearModel(follower)
		return
	end

	local target, forward = BeastFollower.GetTargetPosition(root.Position, root.CFrame.LookVector)
	target = Vector3.new(target.X, 0, target.Z)
	local position = follower.position
	if position then
		local delta = target - position
		local distance = delta.Magnitude
		if distance > settings.SettleDistance and distance < settings.SnapDistance then
			target = position + delta * alpha
		end
	end
	follower.position = target

	local rayOrigin = Vector3.new(target.X, root.Position.Y + settings.GroundProbeAbove, target.Z)
	local ground = workspace:Raycast(rayOrigin,
		Vector3.new(0, -(settings.GroundProbeAbove + settings.GroundProbeBelow), 0), groundParams)
	local groundY = ground and ground.Position.Y or (root.Position.Y - root.Size.Y / 2)
	local bob = math.sin(elapsed * 2 * math.pi * settings.BobFrequency) * settings.BobAmplitude
	local foot = Vector3.new(target.X, groundY + settings.GroundClearance + bob, target.Z)
	local pose = CFrame.lookAt(foot, foot + forward)
	if follower.model then
		follower.model:PivotTo(pose)
	else
		local model = BeastModels.Build(follower.id, pose, settings.BlockSize)
		if model then
			-- Build の原点（足元）を以降の PivotTo でも使う。
			model.WorldPivot = pose
			model:SetAttribute("OwnerUserId", follower.player.UserId)
			model.Parent = folder
			follower.model = model
		end
	end
end

function BeastFollower.Remove(player)
	local follower = followers[player]
	if follower then
		followers[player] = nil
		follower.added:Disconnect()
		follower.removing:Disconnect()
		clearModel(follower)
	end
end

local elapsed = 0
function BeastFollower.SetEquipped(player, id)
	local current = followers[player]
	if current and current.id == id then
		return
	end
	BeastFollower.Remove(player)
	if not id or not Config.Beasts[id] then
		return
	end

	local follower = { player = player, id = id, character = player.Character }
	followers[player] = follower
	follower.added = player.CharacterAdded:Connect(function(character)
		clearModel(follower)
		follower.character = character
		step(follower, 1, elapsed)
	end)
	follower.removing = player.CharacterRemoving:Connect(function(character)
		if follower.character == character then
			follower.character = nil
			clearModel(follower)
		end
	end)
	step(follower, 1, elapsed)
end

RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	local alpha = 1 - math.exp(-settings.FollowRate * dt)
	for _, follower in pairs(followers) do
		step(follower, alpha, elapsed)
	end
end)

return BeastFollower
