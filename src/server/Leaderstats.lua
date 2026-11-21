-- Leaderstats: 「逃げ切り」「鬼タッチ」の2項目をプレイヤーリストに表示する

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Leaderstats = {}

local STAT_KEYS = { "Tagged", "Returns" } -- 試合ごとに 0 に戻す

local function setup(player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	for _, key in ipairs(STAT_KEYS) do
		local value = Instance.new("IntValue")
		value.Name = Config.LeaderstatNames[key]
		value.Value = 0
		value.Parent = folder
	end
	folder.Parent = player
end

function Leaderstats.Init()
	Players.PlayerAdded:Connect(setup)
	for _, player in ipairs(Players:GetPlayers()) do
		setup(player)
	end
end

-- key は "Survived" または "Tagged"
function Leaderstats.Increment(player, key)
	local folder = player and player:FindFirstChild("leaderstats")
	local statName = Config.LeaderstatNames[key]
	if not folder or not statName then
		return
	end
	local value = folder:FindFirstChild(statName)
	if value then
		value.Value = value.Value + 1
	end
end

function Leaderstats.Set(player, key, amount)
	local folder = player and player:FindFirstChild("leaderstats")
	local statName = Config.LeaderstatNames[key]
	local value = folder and statName and folder:FindFirstChild(statName)
	if value then
		value.Value = amount
	end
end

-- 試合の始めに全員の記録を 0 に戻す
function Leaderstats.ResetAll()
	for _, player in ipairs(Players:GetPlayers()) do
		for _, key in ipairs(STAT_KEYS) do
			Leaderstats.Set(player, key, 0)
		end
	end
end

return Leaderstats
