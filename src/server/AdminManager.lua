-- 管理操作の権限・対象・引数をサーバーで検証する。
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local GameState = require(script.Parent:WaitForChild("GameState"))
local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))
local RankManager = require(script.Parent:WaitForChild("RankManager"))
local ItemManager = require(script.Parent:WaitForChild("ItemManager"))
local RoundManager = require(script.Parent:WaitForChild("RoundManager"))

local AdminManager = {}
local remote = Remotes.AdminRequest
local startedAt = os.clock()
local history = {}
local busy = {}
local banPages = {}
local banWrites = {}
local denied = setmetatable({}, { __mode = "k" })
local readOptions = Instance.new("DataStoreGetOptions")
readOptions.UseCache = false
local commands = {}

local function banStore()
	return DataStoreService:GetDataStore("AdminBansV1")
end

local function isAdmin(player)
	return (game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId)
		or table.find(Config.AdminUserIds, player.UserId) ~= nil
end

local function onPlayerAdded(player)
	player:SetAttribute("AdminAdmissionPending", true)
	player:SetAttribute("IsAdmin", false)
	local ok, record = pcall(function()
		return banStore():GetAsync(tostring(player.UserId), readOptions)
	end)
	if player.Parent ~= Players or denied[player] then
		return
	end
	if not ok then
		warn("AdminManager: BAN の確認に失敗", player.UserId, record)
	elseif type(record) == "table" then
		denied[player] = true
		player:Kick("BANされています。理由：" .. (record.Reason or "管理者による利用停止"))
		return
	end
	player:SetAttribute("AdminAdmissionPending", nil)
	player:SetAttribute("IsAdmin", isAdmin(player))
end

local function validNumber(value, maximum)
	return type(value) == "number" and value >= 1 and value <= maximum and value == math.floor(value)
end

local function findPlayer(userId)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

local function filteredText(player, value)
	if type(value) ~= "string" or #value > 600 or not utf8.len(value) or not value:find("%S") then
		return nil
	end
	return TextService:FilterStringAsync(value, player.UserId):GetNonChatStringForBroadcastAsync()
end

local function reasonFor(player, reason, defaultReason)
	if reason == nil or reason == "" then
		return defaultReason
	end
	return filteredText(player, reason)
end

function commands.Kick(player, target, reason)
	local text = reasonFor(player, reason, "管理者によるキック")
	if not text or target.Parent ~= Players then
		return false, "理由または対象を確認してください"
	end
	target:Kick(text)
	return true
end

local function changeBan(userId, record)
	if banWrites[userId] then
		return false, "対象のBANを更新中です"
	end
	banWrites[userId] = true
	local ok, err = pcall(function()
		local store = banStore()
		if record then
			store:SetAsync(tostring(userId), record)
		else
			store:RemoveAsync(tostring(userId))
		end
	end)
	banWrites[userId] = nil
	if not ok then
		warn("AdminManager: BAN の更新に失敗", userId, err)
		return false, "BANの保存先を更新できませんでした"
	end
	return true
end

function commands.Ban(player, target, reason)
	local text = reasonFor(player, reason, "管理者による利用停止")
	if not text then
		return false, "理由を確認してください"
	end
	local ok, message = changeBan(target.UserId, { Reason = text })
	if ok then
		local current = findPlayer(target.UserId)
		if current then
			denied[current] = true
			current:SetAttribute("AdminAdmissionPending", true)
			current:SetAttribute("IsAdmin", false)
			current:Kick("BANされています。理由：" .. text)
		end
	end
	return ok, message
end

function commands.Unban(_, userId)
	if not validNumber(userId, 9007199254740991) then
		return false, "BAN一覧から対象を選んでください"
	end
	return changeBan(userId, nil)
end

function commands.Tagger(_, target)
	return RoundManager.SetAdminTagger(target), "試合中の生存参加者を選んでください"
end

local function teleport(moving, destination)
	local root = GameState.GetRootPart(destination)
	local movingRoot = GameState.GetRootPart(moving)
	if not root or not movingRoot then
		return false, "両方のキャラクターが必要です"
	end
	moving.Character:PivotTo(root.CFrame * CFrame.new(4, 0, 0))
	movingRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	return true
end

function commands.Bring(player, target)
	return teleport(target, player)
end

function commands.GoTo(player, target)
	return teleport(player, target)
end

function commands.Announce(player, text)
	local filtered = filteredText(player, text)
	if not filtered then
		return false, "お知らせを600バイト以内で入力してください"
	end
	Remotes.Notify:FireAllClients(filtered)
	return true
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
	if not validNumber(amount, 1000000) then
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
		History = history,
	}
end

local function listBans(player, action)
	local pages = banPages[player]
	if action == "ListBans" or not pages then
		pages = banStore():ListKeysAsync("", 25, "", true)
	elseif not pages.IsFinished then
		pages:AdvanceToNextPageAsync()
	end
	if player.Parent == Players then
		banPages[player] = pages
	end
	local ids = {}
	for _, entry in ipairs(pages:GetCurrentPage()) do
		local id = tonumber(entry.KeyName)
		if id then
			table.insert(ids, id)
		end
	end
	return { UserIds = ids, HasNext = not pages.IsFinished }
end

local targetCommands = {
	Kick = true, Ban = true, Tagger = true, Bring = true, GoTo = true, GrantItem = true, AwardRP = true,
}

local function audit(player, action, target, ok, detail)
	local entry = string.format("%s (%d) → %s | %s | %s", player.Name, player.UserId, target, action,
		ok and "成功" or "失敗")
	if detail then
		entry ..= " | " .. detail
	end
	print("[Admin]", entry)
	table.insert(history, 1, entry)
	if #history > 20 then
		table.remove(history)
	end
end

local function handleRequest(player, action, first, second)
	if player.Parent ~= Players or not isAdmin(player) or player:GetAttribute("AdminAdmissionPending") == true then
		warn("AdminManager: 権限のない管理リクエスト", player.UserId,
			type(action) == "string" and commands[action] and action or "その他")
		return
	end
	if type(action) ~= "string" or busy[player] then
		return
	end
	busy[player] = true
	local reply = {}
	if action == "ListBans" or action == "NextBans" then
		local ok, result = pcall(listBans, player, action)
		if ok then
			reply.Bans = result
		else
			warn("AdminManager: BAN 一覧の取得に失敗", result)
			reply.Message = "BAN一覧を取得できませんでした"
		end
	elseif commands[action] then
		local target = targetCommands[action] and findPlayer(first) or nil
		local label = action == "Announce" and "サーバー全員" or "サーバー"
		if target then
			label = string.format("%s (%d)", target.Name, target.UserId)
		elseif targetCommands[action] or action == "Unban" then
			label = type(first) == "number" and tostring(first) or "対象未選択"
		end
		local ok, success, message, detail
		if targetCommands[action] and (not target or target:GetAttribute("AdminAdmissionPending") == true) then
			ok, success, message = true, false, "入室中のプレイヤーを選んでください"
		else
			ok, success, message, detail = pcall(commands[action], player, target or first, second)
		end
		if not ok then
			warn("AdminManager: 管理操作に失敗", action, success)
			success, message = false, "操作を完了できませんでした"
		end
		audit(player, action, label, success, detail)
		reply.Message = success and "操作を受け付けました" or (message or "操作を実行できませんでした")
		if success and action == "Unban" then
			reply.Unbanned = first
		end
	elseif action ~= "Status" then
		warn("AdminManager: 未知の管理操作", player.UserId)
		busy[player] = nil
		return
	end
	busy[player] = nil
	if player.Parent == Players then
		reply.Status = snapshot()
		remote:FireClient(player, reply)
	end
end

function AdminManager.Init()
	remote.OnServerEvent:Connect(handleRequest)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		banPages[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return AdminManager
