local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local AdminService = require(script.Parent:WaitForChild("AdminService"))
local PlayerDataStore = require(script.Parent:WaitForChild("PlayerDataStore"))

local LobbyAdmin = {}
local MAX_AWARD = 1000000

local function getRootPart(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

function LobbyAdmin.Init(options)
	local commands = {}

	function commands.AwardCoins(_, target, amount)
		if not AdminService.ValidNumber(amount, MAX_AWARD) then
			return false, "コインは1〜1,000,000の整数で指定してください"
		end
		if not options.IsLoaded(target) then
			return false, "対象のデータを読み込み中です"
		end
		local data, message = PlayerDataStore.AddCoins(target, amount)
		if not data then
			return false, message
		end
		if target.Parent == Players then
			options.SendData(target)
		else
			PlayerDataStore.Forget(target)
		end
		return true, nil, tostring(amount) .. " コイン"
	end

	function commands.AwardRP(_, target, amount)
		if not AdminService.ValidNumber(amount, MAX_AWARD) then
			return false, "RPは1〜1,000,000の整数で指定してください"
		end
		if not options.IsLoaded(target) then
			return false, "対象のデータを読み込み中です"
		end
		if not options.RankStore then
			return false, "RPの保存先を取得できませんでした"
		end
		local key = tostring(target.UserId)
		local saved = options.RankStore:UpdateAsync(key, function(old)
			local rank = type(old) == "table" and old or {}
			rank.RP = math.max(0, math.floor(tonumber(rank.RP) or 0)) + amount
			return rank
		end)
		if target.Parent == Players then
			options.ShowRP(target, saved.RP)
		end
		local detail = tostring(amount) .. " RP"
		if not options.WriteLeaderboard(key, saved.RP) then
			detail ..= "（ランキングへの反映に失敗）"
		end
		return true, nil, detail
	end

	function commands.GrantBeast(_, target, id)
		if not options.IsLoaded(target) then
			return false, "対象のデータを読み込み中です"
		end
		local ok, message = PlayerDataStore.GrantBeast(target, id)
		if target.Parent ~= Players then
			PlayerDataStore.Forget(target)
		elseif ok then
			options.SendData(target)
		end
		if not ok then
			return false, message
		end
		return true, nil, id
	end

	local function snapshot()
		local players = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if options.IsLoaded(player) and player:GetAttribute("AdminAdmissionPending") ~= true then
				local rp = options.GetRP(player)
				table.insert(players, {
					UserId = player.UserId,
					Name = player.Name,
					Rank = Config.TierForRP(rp).Name,
					RP = rp,
				})
			end
		end
		table.sort(players, function(a, b) return a.Name:lower() < b.Name:lower() end)
		return { Players = players }
	end

	return AdminService.new({
		Remote = options.Remote,
		Notify = options.Notify,
		GetRootPart = getRootPart,
		Commands = commands,
		TargetCommands = { AwardCoins = true, AwardRP = true, GrantBeast = true },
		Snapshot = snapshot,
	})
end

return LobbyAdmin
