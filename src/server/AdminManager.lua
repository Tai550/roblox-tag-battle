-- 管理操作の権限・対象・引数をサーバーで検証する。
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local GameState = require(script.Parent:WaitForChild("GameState"))
local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))
local RankManager = require(script.Parent:WaitForChild("RankManager"))
local ItemManager = require(script.Parent:WaitForChild("ItemManager"))
local RoundManager = require(script.Parent:WaitForChild("RoundManager"))

local AdminService = require(script.Parent:WaitForChild("AdminService"))

local AdminManager = {}
local commands = {}
local startedAt = os.clock()

function commands.Tagger(_, target)
	return RoundManager.SetAdminTagger(target), "試合中の生存参加者を選んでください"
end

function commands.StartRound()
	return RoundManager.RequestStart(), "すでに試合中か、開始できるプレイヤーがいません"
end

function commands.EndRound()
	return RoundManager.RequestEnd(), "終了できる試合がありません"
end

function commands.NextMap()
	return RoundManager.RequestNextMap(), "すでにマップ切り替えを予約しています"
end

function commands.SetBots(_, enabled)
	if type(enabled) ~= "boolean" then
		return false, "補充の有効・無効を指定してください"
	end
	Config.BotsEnabled = enabled
	return true, nil, enabled and "補充オン" or "補充オフ"
end

function commands.GrantItem(_, target, itemId)
	if type(itemId) ~= "string" or not ItemManager.GrantItem(target, itemId) then
		return false, "アイテムを確認してください"
	end
	return true, nil, itemId
end

function commands.AwardRP(_, target, amount)
	if not AdminService.ValidNumber(amount, 1000000) then
		return false, "RPは1〜1,000,000の整数で指定してください"
	end
	return RankManager.Award(target, amount) ~= nil, nil, tostring(amount) .. " RP"
end

local function snapshot()
	local humans, bots = 0, 0
	for _, participant in ipairs(GameState.ParticipantList()) do
		if type(participant) == "table" and participant.IsBot then
			bots += 1
		else
			humans += 1
		end
	end
	local players = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("AdminAdmissionPending") ~= true then
			local rp = RankManager.Get(player).RP
			table.insert(players, {
				UserId = player.UserId,
				Name = player.Name,
				Rank = Config.TierForRP(rp).Name,
				RP = rp,
				Participating = GameState.Phase == "Round" and GameState.IsParticipant(player),
			})
		end
	end
	table.sort(players, function(a, b) return a.Name:lower() < b.Name:lower() end)
	return {
		Players = players,
		Map = MapBuilder.GetCurrentMapInfo().Name,
		Phase = GameState.Phase,
		Humans = humans,
		Bots = bots,
		BotsEnabled = Config.BotsEnabled,
		Uptime = math.floor(os.clock() - startedAt),
	}
end

local targetCommands = {
	Tagger = true, GrantItem = true, AwardRP = true,
}

function AdminManager.Init()
	local onPlayerAdded = AdminService.new({
		Remote = Remotes.AdminRequest,
		Notify = Remotes.Notify,
		GetRootPart = GameState.GetRootPart,
		Commands = commands,
		TargetCommands = targetCommands,
		Snapshot = snapshot,
	})
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return AdminManager
