-- Leaderstats: プレイヤーリストの項目
--   鬼回数・送還 … この試合の記録（試合ごとに 0 に戻す）
--   ランク・RP   … 累計の段位（RankManager が保存・書き戻しする）

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Leaderstats = {}

-- 並び順がプレイヤーリストの列順になる
local STAT_DEFS = {
	{ Key = "Tagged", ClassName = "IntValue", PerMatch = true },
	{ Key = "Returns", ClassName = "IntValue", PerMatch = true },
	{ Key = "Rank", ClassName = "StringValue" },
	{ Key = "RP", ClassName = "IntValue" },
}

-- 本物のプレイヤーだけ（ボットはプレーンなテーブルなので記録を付けない）
local function isRealPlayer(player)
	return player ~= nil and not (type(player) == "table" and player.IsBot == true)
end

local function defaultValue(def)
	if def.ClassName == "StringValue" then
		local tier = Config.TierForRP(0)
		return tier and tier.Name or ""
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
	if not isRealPlayer(player) or player:FindFirstChild("leaderstats") then
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

-- 数値の項目を +1 する。項目がなければ何もしない
function Leaderstats.Increment(player, key)
	if not isRealPlayer(player) then
		return
	end
	local value = findStat(player, key)
	if value and type(value.Value) == "number" then
		value.Value = value.Value + 1
	end
end

function Leaderstats.Set(player, key, value)
	if not isRealPlayer(player) then
		return
	end
	local stat = findStat(player, key)
	if stat then
		stat.Value = value
	end
end

-- 試合の始めに、この試合の記録だけ 0 に戻す（ランクと RP はそのまま）
function Leaderstats.ResetAll()
	for _, player in ipairs(Players:GetPlayers()) do
		for _, def in ipairs(STAT_DEFS) do
			if def.PerMatch then
				Leaderstats.Set(player, def.Key, 0)
			end
		end
	end
end

return Leaderstats
