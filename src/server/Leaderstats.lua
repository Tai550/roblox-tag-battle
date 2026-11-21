-- Leaderstats: プレイヤーリストに「逃げ切り」「鬼タッチ」「ランク」「RP」を出す
-- 表示用の値を置く場所。累計の保存と段位の判定は RankManager が行う。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Leaderstats = {}

-- ボットは leaderstats を持たない。プレーンなテーブルに FindFirstChild しない。
local function isBot(player)
	return type(player) == "table" and player.IsBot == true
end

-- 並び順がプレイヤーリストの列順になる。ランクと RP は後ろに足す。
local STAT_DEFS = {
	{ Key = "Survived", ClassName = "IntValue" },
	{ Key = "Tagged", ClassName = "IntValue" },
	{ Key = "Rank", ClassName = "StringValue" },
	{ Key = "RP", ClassName = "IntValue" },
}

local function startingRankName()
	local tier = Config.TierForRP(0)
	if tier then
		return tier.Name
	end
	return ""
end

local function defaultValue(def)
	if def.ClassName == "StringValue" then
		return startingRankName()
	end
	return 0
end

local function findStat(player, key)
	local folder = player and player:FindFirstChild("leaderstats")
	local statName = Config.LeaderstatNames[key]
	if not folder or not statName then
		return nil
	end
	return folder:FindFirstChild(statName)
end

local function setup(player)
	if isBot(player) then
		return
	end
	if player:FindFirstChild("leaderstats") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	for _, def in ipairs(STAT_DEFS) do
		local value = Instance.new(def.ClassName)
		value.Name = Config.LeaderstatNames[def.Key]
		value.Value = defaultValue(def)
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

-- key は "Survived" または "Tagged"（数値の項目だけ +1 する）
function Leaderstats.Increment(player, key)
	if isBot(player) then
		return
	end
	local value = findStat(player, key)
	if value and type(value.Value) == "number" then
		value.Value = value.Value + 1
	end
end

-- RankManager が累計を書き戻すときに使う。項目がなければ何もしない。
function Leaderstats.Set(player, key, value)
	if isBot(player) then
		return
	end
	local stat = findStat(player, key)
	if stat then
		stat.Value = value
	end
end

return Leaderstats
