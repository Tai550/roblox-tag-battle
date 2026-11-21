-- MatchSession: この試合サーバーの「遊び方」と、ロビーへの移動
--
--   Quick   : ロビーの「すぐ遊ぶ」から来た部屋。1試合だけ遊んで全員ロビーへ戻る
--   Friends : 合言葉で集まった友達部屋。ホストが「開始」を押すたびに何試合でも遊べる
--   Studio  : Studio でのテスト。人数がそろえば自動で何度でも始まる（移動はしない）
--   Stray   : 予約サーバー以外から直接入ってきた場合。ロビーへ送り返す

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local MatchSession = {}

MatchSession.Mode = "Studio"
MatchSession.Expected = 0       -- Quick: ロビーから一緒に来る予定の人数
MatchSession.Code = ""          -- Friends: 合言葉
MatchSession.StartRequested = false

local hostUserId = 0
local joinOrder = {}            -- 入ってきた順の Player（ホストの引き継ぎ用）
local modeDecided = false

local function isReservedServer()
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

-- ロビーへ送る（Studio では移動できないので、知らせるだけ）
function MatchSession.SendToLobby(players)
	if #players == 0 then
		return
	end
	if RunService:IsStudio() then
		for _, player in ipairs(players) do
			Remotes.NotifyPlayer(player, "（Studio ではロビーへ移動できません）")
		end
		return
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Config.LobbyPlaceId, players)
	end)
	if not ok then
		warn("[MatchSession] ロビーへの移動に失敗: " .. tostring(err))
		for _, player in ipairs(players) do
			Remotes.NotifyPlayer(player, "ロビーへの移動に失敗しました。もう一度「ロビーへ」を押してね")
		end
	end
end

function MatchSession.GetHost()
	for _, player in ipairs(joinOrder) do
		if player.Parent == Players and player.UserId == hostUserId then
			return player
		end
	end
	-- ホストがいなければ、いちばん先に来た人が引き継ぐ
	for _, player in ipairs(joinOrder) do
		if player.Parent == Players then
			hostUserId = player.UserId
			return player
		end
	end
	return nil
end

function MatchSession.GetHostUserId()
	local host = MatchSession.GetHost()
	return host and host.UserId or 0
end

local function readTeleportData(player)
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if ok and type(joinData) == "table" and type(joinData.TeleportData) == "table" then
		return joinData.TeleportData
	end
	return nil
end

local function onPlayerAdded(player)
	table.insert(joinOrder, player)
	local data = readTeleportData(player)
	if not modeDecided and data and (data.Mode == "Quick" or data.Mode == "Friends") then
		modeDecided = true
		MatchSession.Mode = data.Mode
		MatchSession.Expected = tonumber(data.Expected) or 0
		MatchSession.Code = type(data.Code) == "string" and data.Code or ""
		hostUserId = tonumber(data.HostUserId) or player.UserId
	end
	if MatchSession.Mode == "Stray" then
		Remotes.NotifyPlayer(player, "ロビーへ移動します…")
		task.delay(2, function()
			if player.Parent == Players then
				MatchSession.SendToLobby({ player })
			end
		end)
	end
end

function MatchSession.Init()
	if RunService:IsStudio() then
		MatchSession.Mode = "Studio"
		modeDecided = true
	elseif not isReservedServer() then
		MatchSession.Mode = "Stray"
		modeDecided = true
	else
		MatchSession.Mode = "Quick" -- 最初のプレイヤーの TeleportData で確定する
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		for index, other in ipairs(joinOrder) do
			if other == player then
				table.remove(joinOrder, index)
				break
			end
		end
	end)

	Remotes.HostStart.OnServerEvent:Connect(function(player)
		if MatchSession.Mode == "Friends" and player == MatchSession.GetHost() then
			MatchSession.StartRequested = true
		end
	end)
	Remotes.LeaveToLobby.OnServerEvent:Connect(function(player)
		MatchSession.SendToLobby({ player })
	end)
end

return MatchSession
