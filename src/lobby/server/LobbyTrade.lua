local LobbyTrade = {}
local OTHER_OWNS = "相手が既にその召喚獣を所持しているため交換できません"
local YOU_OWN = "受け取る召喚獣を既に所持しているため交換できません"

function LobbyTrade.new(options)
	local active = {}
	local nextId = 0
	local function present(player)
		return options.FindPlayer(player.UserId) == player and options.IsLoaded(player)
	end

	local function send(player, state, message)
		if present(player) then
			options.Send(player, state, message)
		end
	end

	local function duplicates(trade)
		return options.Owns(trade.B, trade.OfferA),
			trade.OfferB ~= nil and options.Owns(trade.A, trade.OfferB)
	end

	local function broadcast(trade)
		local bOwns, aOwns = duplicates(trade)
		trade.BOwns, trade.AOwns = bOwns, aOwns
		for _, player in ipairs({ trade.A, trade.B }) do
			send(player, {
				Id = trade.Id,
				Phase = trade.Phase,
				From = trade.A.DisplayName,
				To = trade.B.DisplayName,
				OfferA = trade.OfferA,
				OfferB = trade.OfferB,
				IsSender = player == trade.A,
				BlockedReason = (player == trade.A and bOwns or player == trade.B and aOwns) and OTHER_OWNS
					or (bOwns or aOwns) and YOU_OWN or nil,
				Confirmed = trade.Confirmed[player] == true,
			})
		end
	end

	local function finish(trade, message, departed)
		if trade.Ended then
			return
		end
		trade.Ended = true
		for _, player in ipairs({ trade.A, trade.B }) do
			if trade.Phase ~= "saving" then
				active[player.UserId] = nil
			end
			if player ~= departed then
				send(player, { Phase = "idle" }, message)
			end
		end
	end

	local function valid(trade)
		if trade.Ended then
			return false
		end
		if not present(trade.A) or not present(trade.B) then
			finish(trade, "相手がロビーを離れたため、交換を取り消しました")
			return false
		end
		if options.Now() >= trade.ExpiresAt then
			finish(trade, "交換の期限が切れました")
			return false
		end
		return true
	end

	local function request(player, targetId, id)
		if type(targetId) ~= "number" or targetId % 1 ~= 0 or math.abs(targetId) >= 2^53
			or targetId == player.UserId then
			send(player, nil, "交換する相手を選んでください")
			return
		end
		local target = options.FindPlayer(targetId)
		if not target or not present(target) then
			send(player, nil, "相手は交換できる状態ではありません")
			return
		end
		if options.IsTradePending and (options.IsTradePending(player) or options.IsTradePending(target)) then
			send(player, nil, "未完了の交換があるため交換できません")
			return
		end
		if active[player.UserId] or active[targetId] then
			send(player, nil, "すでに交換中のため申し込めません")
			return
		end
		if type(id) ~= "string" or not options.Owns(player, id) then
			send(player, nil, "持っている召喚獣を選んでください")
			return
		end
		if options.Owns(target, id) then
			send(player, nil, OTHER_OWNS)
			return
		end
		nextId += 1
		local trade = {
			Id = nextId,
			A = player,
			B = target,
			OfferA = id,
			Phase = "offered",
			Confirmed = {},
			ExpiresAt = options.Now() + options.Timeout,
		}
		active[player.UserId], active[targetId] = trade, trade
		broadcast(trade)
	end

	local function handle(player, action, target, id)
		if not present(player) then
			return
		end
		if action == "request" then
			request(player, target, id)
			return
		end
		local trade = active[player.UserId]
		if not trade or (trade.A ~= player and trade.B ~= player) or trade.Id ~= target or not valid(trade) then
			return
		end
		if action == "cancel" then
			finish(trade, "交換を取り消しました")
		elseif action == "offer" and trade.B == player and trade.Phase == "offered" then
			if type(id) ~= "string" or id == trade.OfferA or not options.Owns(player, id) then
				send(player, nil, "相手と異なる、持っている召喚獣を選んでください")
				return
			end
			if not options.Owns(trade.A, trade.OfferA) then
				finish(trade, "交換に出した召喚獣が所持品にありません")
				return
			end
			if options.Owns(player, trade.OfferA) then
				finish(trade, YOU_OWN)
				return
			end
			if options.Owns(trade.A, id) then
				send(player, nil, OTHER_OWNS)
				return
			end
			trade.OfferB = id
			trade.Phase = "confirming"
			broadcast(trade)
		elseif action == "confirm" and trade.Phase == "confirming" and not trade.Confirmed[player] then
			local bOwns, aOwns = duplicates(trade)
			if bOwns or aOwns then
				broadcast(trade)
				return
			end
			trade.Confirmed[player] = true
			if not (trade.Confirmed[trade.A] and trade.Confirmed[trade.B]) then
				broadcast(trade)
				return
			end
			if not options.Owns(trade.A, trade.OfferA) or not options.Owns(trade.B, trade.OfferB) then
				finish(trade, "交換に出した召喚獣が所持品にありません")
				return
			end
			trade.Phase = "saving"
			broadcast(trade)
			local ok, reason = options.Save(trade.A, trade.OfferA, trade.B, trade.OfferB, function()
				return valid(trade)
			end)
			for _, participant in ipairs({ trade.A, trade.B }) do
				if present(participant) then
					options.Refresh(participant)
				end
			end
			trade.Phase = "finished"
			active[trade.A.UserId], active[trade.B.UserId] = nil, nil
			finish(trade, ok and "召喚獣の交換が成立しました" or reason or "召喚獣を交換できませんでした")
		end
	end

	return {
		Handle = handle,
		Tick = function()
			for _, trade in pairs(active) do
				if valid(trade) and trade.Phase ~= "saving" then
					local bOwns, aOwns = duplicates(trade)
					if bOwns ~= trade.BOwns or aOwns ~= trade.AOwns then
						broadcast(trade)
					end
				end
			end
		end,
		Remove = function(player)
			local trade = active[player.UserId]
			if trade and (trade.A == player or trade.B == player) then
				finish(trade, "相手がロビーを離れたため、交換を取り消しました", player)
			end
		end,
	}
end

return LobbyTrade
