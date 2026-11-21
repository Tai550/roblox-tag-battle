local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local AdminService = {}

local function banStore()
	return DataStoreService:GetDataStore("AdminBansV1")
end

local function isAdmin(player)
	return (game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId)
		or table.find(Config.AdminUserIds, player.UserId) ~= nil
end

function AdminService.ValidNumber(value, maximum)
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

function AdminService.new(options)
	local history = {}
	local busy = {}
	local banPages = {}
	local banWrites = {}
	local denied = setmetatable({}, { __mode = "k" })
	local readOptions = Instance.new("DataStoreGetOptions")
	readOptions.UseCache = false
	local commands = options.Commands
	local targetCommands = options.TargetCommands
	targetCommands.Kick = true
	targetCommands.Ban = true
	targetCommands.Bring = true
	targetCommands.GoTo = true

	local function onPlayerAdded(player)
		player:SetAttribute("AdminAdmissionPending", true)
		player:SetAttribute("IsAdmin", false)
		local ok, record
		for attempt = 1, 3 do
			if player.Parent ~= Players or denied[player] then
				return
			end
			ok, record = pcall(function()
				return banStore():GetAsync(tostring(player.UserId), readOptions)
			end)
			if ok then
				break
			end
			warn("AdminManager: BAN の確認に失敗", player.UserId, record)
			if attempt < 3 then
				task.wait(attempt)
			end
		end
		if player.Parent ~= Players or denied[player] then
			return
		end
		if not ok then
			denied[player] = true
			player:Kick("入場を確認できませんでした。時間をおいて再接続してください")
			return
		elseif type(record) == "table" then
			denied[player] = true
			player:Kick("BANされています。理由：" .. (record.Reason or "管理者による利用停止"))
			return
		end
		player:SetAttribute("AdminAdmissionPending", nil)
		player:SetAttribute("IsAdmin", isAdmin(player))
		return true
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
		if not AdminService.ValidNumber(userId, 9007199254740991) then
			return false, "BAN一覧から対象を選んでください"
		end
		return changeBan(userId, nil)
	end

	local function teleport(moving, destination)
		local root = options.GetRootPart(destination)
		local movingRoot = options.GetRootPart(moving)
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
		options.Notify:FireAllClients(filtered)
		return true
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
		if player.Parent ~= Players or not isAdmin(player)
			or player:GetAttribute("IsAdmin") ~= true or player:GetAttribute("AdminAdmissionPending") == true then
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
			audit(player, action, "BAN一覧", ok)
			if ok then
				reply.Bans = result
				reply.Message = "BAN一覧を取得しました"
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
			reply.Status = options.Snapshot()
			reply.Status.History = history
			options.Remote:FireClient(player, reply)
		end
	end

	options.Remote.OnServerEvent:Connect(handleRequest)
	Players.PlayerRemoving:Connect(function(player)
		banPages[player] = nil
	end)
	return onPlayerAdded
end

return AdminService
