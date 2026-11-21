local RT = require("./.build/mockenv")
local LobbyTrade = require("./.build/LobbyTrade")

return function(check)
	local config = RT.modules.Config
	local data = RT.modules.PlayerDataStore
	local stores = RT.game:GetService("DataStoreService")
	local store = stores:GetDataStore("PlayerData_v1")
	local journal = stores:GetDataStore("BeastTradePendingV1")
	local a = { UserId = 48101, DisplayName = "A" }
	local b = { UserId = 48102, DisplayName = "B" }
	local c = { UserId = 48103, DisplayName = "C" }
	local keyA, keyB = "u_" .. a.UserId, "u_" .. b.UserId
	local aId, bId = "Bastet", "Thoth"
	local players, states, notices, refreshes = {}, {}, {}, {}
	local now = 0
	local trade = LobbyTrade.new({
		Timeout = config.BeastTradeTimeout,
		Now = function() return now end,
		FindPlayer = function(id) return players[id] end,
		IsLoaded = function() return true end,
		Owns = function(player, id) return data.Get(player).Beasts[id] == true end,
		Send = function(player, state, message)
			states[player] = state or states[player]
			notices[player] = message
		end,
		Save = data.TradeBeasts,
		IsTradePending = data.IsTradePending,
		Refresh = function(player)
			refreshes[player] = data.Get(player)
		end,
	})

	local function reset()
		now = 0
		players[a.UserId], players[b.UserId], players[c.UserId] = a, b, c
		table.clear(states)
		table.clear(notices)
		table.clear(refreshes)
		store:SetAsync(keyA, { Beasts = { [aId] = true }, EquippedBeast = aId })
		store:SetAsync(keyB, { Beasts = { [bId] = true }, EquippedBeast = bId })
		data.Load(a)
		data.Load(b)
	end

	local function propose()
		trade.Handle(a, "request", b.UserId, aId)
		local token = states[a].Id
		trade.Handle(b, "offer", token, bId)
		return token
	end

	local function accept(token)
		trade.Handle(a, "confirm", token)
		trade.Handle(b, "confirm", token)
	end

	reset()
	trade.Handle(a, "request", b.UserId, bId)
	check("交換: 未所持の獣で申し込めない", not states[a] and notices[a] and not states[b])
	trade.Handle(a, "request", a.UserId, aId)
	trade.Handle(a, "request", 49999, aId)
	check("交換: 自分や不在の相手に申し込めない", not states[a] and notices[a])
	trade.Handle(a, "request", b.UserId, aId)
	local id = states[a].Id
	trade.Handle(b, "offer", id, aId)
	trade.Handle(b, "offer", id, "Ra")
	check("交換: 同じ獣や未所持の獣では応答できない", states[b].Phase == "offered" and notices[b])
	trade.Handle(b, "offer", id, bId)
	trade.Handle(a, "confirm", id)
	check("交換: 片方の決定だけでは保存しない", store:GetAsync(keyA).Beasts[aId] and states[a].Confirmed)
	trade.Handle(b, "confirm", id - 1)
	check("交換: 古い決定は無効", states[b].Phase == "confirming")
	trade.Handle(b, "confirm", id)
	local savedA, savedB = store:GetAsync(keyA), store:GetAsync(keyB)
	check("交換: 双方が決定すると保存とキャッシュの所持が入れ替わる",
		savedA.Beasts[bId] and not savedA.Beasts[aId] and savedB.Beasts[aId] and not savedB.Beasts[bId]
		and refreshes[a].Beasts[bId] and refreshes[b].Beasts[aId])
	check("交換: 出した獣は双方の装備から外れる",
		not savedA.EquippedBeast and not savedB.EquippedBeast
		and not refreshes[a].EquippedBeast and not refreshes[b].EquippedBeast
		and states[a].Phase == "idle" and notices[a] == notices[b])

	reset()
	id = propose()
	data.Get(b).Beasts[bId] = nil
	accept(id)
	check("交換: 成立直前に未所持なら双方の保存を変更しない",
		states[a].Phase == "idle" and notices[a] and notices[a] == notices[b]
		and store:GetAsync(keyA).Beasts[aId] and store:GetAsync(keyB).Beasts[bId] and not refreshes[a])

	reset()
	id = propose()
	store:SetAsync(keyB, { Beasts = {} })
	accept(id)
	check("交換: キャッシュに残っていても保存先で未所持なら片側の保存を復元",
		not store:GetAsync(keyA).Beasts[bId] and store:GetAsync(keyA).EquippedBeast == aId
		and not store:GetAsync(keyB).Beasts[aId] and notices[a] and notices[a] == notices[b])

	reset()
	data.GrantBeast(c, "Ra")
	trade.Handle(a, "request", b.UserId, aId)
	trade.Handle(a, "request", c.UserId, aId)
	local senderBusy = notices[a] and not states[c]
	trade.Handle(c, "request", b.UserId, "Ra")
	check("交換: 申し込み側・受ける側の二重参加を拒否", senderBusy and notices[c] and not states[c])
	players[b.UserId] = nil
	trade.Remove(b)
	check("交換: 相手が退出すると即座に残った人へ通知", states[a].Phase == "idle" and notices[a])
	trade.Handle(a, "request", c.UserId, aId)
	check("交換: 退出による取り消し後は新しく申し込める", states[c] and states[c].Phase == "offered")
	trade.Handle(c, "cancel", states[c].Id)
	check("交換: 断ると双方が待機に戻る", states[a].Phase == "idle" and states[c].Phase == "idle"
		and notices[a] and notices[a] == notices[c])

	reset()
	id = propose()
	now = 59
	trade.Tick()
	local beforeDeadline = states[a].Phase == "confirming"
	now = 60
	trade.Tick()
	check("交換: 申し込みから60秒で期限切れ", beforeDeadline and states[a].Phase == "idle"
		and states[b].Phase == "idle" and notices[a] and notices[a] == notices[b])

	reset()
	data.GrantBeast(b, aId)
	trade.Handle(a, "request", b.UserId, aId)
	check("交換: 相手が所持済みなら申し込みを拒否", not states[a] and notices[a]:find("所持"))

	reset()
	trade.Handle(a, "request", b.UserId, aId)
	id = states[a].Id
	data.GrantBeast(a, bId)
	trade.Handle(b, "offer", id, bId)
	check("交換: 応答の獣を申し込み側が所持済みなら拒否",
		states[b].Phase == "offered" and notices[b]:find("所持"))
	trade.Handle(a, "cancel", id)

	reset()
	id = propose()
	data.GrantBeast(b, aId)
	accept(id)
	check("交換: 確認中の重複を双方に表示して成立させない",
		states[a].BlockedReason:find("相手") and states[b].BlockedReason
		and not states[a].Confirmed and not refreshes[a])
	trade.Handle(a, "cancel", id)

	reset()
	id = propose()
	trade.Handle(a, "confirm", id)
	store:SetAsync(keyB, { Beasts = { [aId] = true, [bId] = true }, EquippedBeast = bId })
	trade.Handle(b, "confirm", id)
	check("交換: 確認後に保存先で獲得した獣も重複として拒否",
		states[a].Phase == "idle" and notices[a]:find("既に所持")
		and store:GetAsync(keyA).Beasts[aId] and not store:GetAsync(keyA).Beasts[bId]
		and store:GetAsync(keyB).Beasts[aId] and store:GetAsync(keyB).Beasts[bId])

	reset()
	id = propose()
	local updateAsync = store.UpdateAsync
	store.UpdateAsync = function(self, key, transform)
		local result = updateAsync(self, key, transform)
		if key == keyA and result and result.Beasts[bId] then
			self:SetAsync(keyB, { Beasts = { [aId] = true, [bId] = true }, EquippedBeast = bId })
		end
		return result
	end
	accept(id)
	store.UpdateAsync = updateAsync
	check("交換: 片側の保存中に相手が獲得した場合も交換を取り消し、獲得した獣を保持する",
		notices[b]:find("既に所持") and store:GetAsync(keyA).EquippedBeast == aId
		and not store:GetAsync(keyA).Beasts[bId] and store:GetAsync(keyB).Beasts[aId]
		and store:GetAsync(keyB).Beasts[bId] and not journal:GetAsync(keyA))

	reset()
	id = propose()
	local attempts = 0
	store.UpdateAsync = function(self, key, transform)
		if key == keyB and attempts < 3 then
			attempts += 1
			error("交換テスト: B の保存失敗")
		end
		return updateAsync(self, key, transform)
	end
	accept(id)
	store.UpdateAsync = updateAsync
	savedA, savedB = store:GetAsync(keyA), store:GetAsync(keyB)
	check("交換: B の保存失敗で A の所持と装備を復元しログを消す",
		savedA.Beasts[aId] and not savedA.Beasts[bId] and savedA.EquippedBeast == aId
		and savedB.Beasts[bId] and not savedB.Beasts[aId] and savedB.EquippedBeast == bId
		and data.Get(a).Beasts[aId] and not data.Get(a).Beasts[bId] and data.Get(a).EquippedBeast == aId
		and not journal:GetAsync(keyA) and not journal:GetAsync(keyB)
		and states[a].Phase == "idle" and notices[a] and notices[a] == notices[b])

	reset()
	id = propose()
	store.UpdateAsync = function(self, key, transform)
		local result = updateAsync(self, key, transform)
		if key == keyA and result and result.Beasts[bId] then
			players[b.UserId] = nil
			trade.Remove(b)
		end
		return result
	end
	accept(id)
	store.UpdateAsync = updateAsync
	check("交換: 片側の保存中に退出すると相手に通知して保存を復元する",
		states[a].Phase == "idle" and notices[a] and not refreshes[b]
		and store:GetAsync(keyA).Beasts[aId] and not store:GetAsync(keyA).Beasts[bId]
		and store:GetAsync(keyB).Beasts[bId] and data.Get(a).EquippedBeast == aId)

	reset()
	id = propose()
	local attempts = 0
	store.UpdateAsync = function(self, key, transform)
		local result = updateAsync(self, key, transform)
		if key == keyB and attempts < 3 then
			attempts += 1
			error("交換テスト: B は保存済みだが応答が失われた")
		end
		return result
	end
	accept(id)
	store.UpdateAsync = updateAsync
	check("交換: 保存の応答が全回失われても適用済みの両側を復元",
		attempts == 3 and store:GetAsync(keyA).EquippedBeast == aId and store:GetAsync(keyB).EquippedBeast == bId
		and not data.Get(a).Beasts[bId] and not data.Get(b).Beasts[aId] and notices[a] == notices[b])

	reset()
	id = propose()
	local attemptedA = false
	store.UpdateAsync = function(self, key, transform)
		if key == keyB or attemptedA then
			error("交換テスト: B の保存と A の復元が失敗")
		end
		attemptedA = true
		return updateAsync(self, key, transform)
	end
	accept(id)
	store.UpdateAsync = updateAsync
	check("交換: 復元に失敗した側のキャッシュは最後に確認できた保存結果を維持",
		store:GetAsync(keyA).Beasts[bId] and data.Get(a).Beasts[bId] and not data.Get(a).Beasts[aId]
		and store:GetAsync(keyB).Beasts[bId] and data.Get(b).Beasts[bId] and notices[a] == notices[b])

	local pendingId = journal:GetAsync(keyA)
	local pendingKey = "trade_" .. tostring(pendingId)
	local pending = journal:GetAsync(pendingKey)
	check("交換: 復元失敗後は双方から参照できるログが残る",
		pendingId and journal:GetAsync(keyB) == pendingId and pending.Stage == "rollback"
		and pending.Sides[1].Before.Equipped == aId and pending.Sides[2].Before.Equipped == bId)
	trade.Handle(a, "request", c.UserId, bId)
	check("交換: 復元待ちの間は新しい申し込みを拒否", notices[a]:find("未完了") and not states[c])
	data.Forget(a)
	data.Forget(b)
	local rejoined = { UserId = b.UserId }
	local restored = data.Load(rejoined)
	check("交換: 片側の再入場で双方を復元しログを消す",
		restored.Beasts[bId] and restored.EquippedBeast == bId
		and store:GetAsync(keyA).Beasts[aId] and not store:GetAsync(keyA).Beasts[bId]
		and store:GetAsync(keyA).EquippedBeast == aId and not journal:GetAsync(pendingKey)
		and not journal:GetAsync(keyA) and not journal:GetAsync(keyB))
	data.Forget(rejoined)

	for _, player in ipairs({ a, b, c }) do
		data.Forget(player)
		store:RemoveAsync("u_" .. player.UserId)
	end
end
