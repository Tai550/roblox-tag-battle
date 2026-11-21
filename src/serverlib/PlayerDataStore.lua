-- PlayerDataStore: プレイヤーの保存データ（コイン・持っているアイテム・デッキ）
-- ロビーと試合の両方のサーバーから使う。DataStore への書き込みは必ず UpdateAsync で
-- 「その場で読み直して足す」形にし、ロビーと試合で同時に書いても上書きし合わないようにする。
--
-- 保存形式（キー "u_<UserId>"）:
--   { Coins = 数, Owned = { [アイテムId] = true }, Deck = { アイテムId, ... }, Wins = 数,
--     Beasts = { [召喚獣Id] = true }, EquippedBeast = Id,
--     Trails = { [トレイルId] = true }, EquippedTrail = Id, ItemBoxes = 未受領の数,
--     ItemBoxReceipts = 処理済み購入ID, ItemBoxClaims = 試合内で受け渡し中の数,
--     RouletteStock = ルーレットを回せる回数, RouletteAt = 権利を数え始めた時刻（os.time。0 は未開始） }
--
-- DataStore が使えない環境では、
-- メモリ上のデータで遊べるようにする（保存はされない）。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local PlayerDataStore = {}

local STORE_NAME = "PlayerData_v1"
local RETRIES = 3
local SAVE_FAILED = "データを保存できませんでした。もう一度お試しください"

local store = nil        -- DataStore（初めて使うときに取得する）
local storeFailed = false
local loadStates = {} -- [Player] = "Loading", "Loaded", "Failed"
local cache = {}         -- [Player] = データ
local activeWrites = {}  -- [UserId] = 通常の保存件数
local trading = {}       -- [UserId] = 交換の保存中

---------------------------------------------------------------------
-- 計算だけの関数（テストからも呼べる）
---------------------------------------------------------------------

-- 壊れたデータや古い形式を、正しい形にそろえて返す
function PlayerDataStore.Normalize(raw)
	local data = type(raw) == "table" and raw or {}
	local boxes = tonumber(data.ItemBoxes) or 0
	local result = {
		Coins = math.max(0, math.floor(tonumber(data.Coins) or 0)),
		Owned = {},
		Deck = {},
		Beasts = {},
		Trails = {},
		ItemBoxReceipts = {},
		ItemBoxClaims = {},
		ItemBoxes = boxes > 0 and boxes < math.huge and math.floor(boxes) or 0,
		Wins = math.max(0, math.floor(tonumber(data.Wins) or 0)),
		RouletteStock = math.clamp(math.floor(tonumber(data.RouletteStock) or 0), 0, Config.Roulette.MaxStock),
		RouletteAt = math.max(0, math.floor(tonumber(data.RouletteAt) or 0)),
	}
	if type(data.ItemBoxReceipts) == "table" then
		for id, recorded in pairs(data.ItemBoxReceipts) do
			if type(id) == "string" and recorded == true then
				result.ItemBoxReceipts[id] = true
			end
		end
	end
	if type(data.ItemBoxClaims) == "table" then
		for id, count in pairs(data.ItemBoxClaims) do
			if type(id) == "string" and type(count) == "number" and count > 0 and count < math.huge then
				result.ItemBoxClaims[id] = math.floor(count)
			end
		end
	end
	if type(data.Owned) == "table" then
		for itemId, owned in pairs(data.Owned) do
			if owned == true and Config.Items[itemId] then
				result.Owned[itemId] = true
			end
		end
	end
	for _, itemId in ipairs(Config.StarterItems) do
		result.Owned[itemId] = true
	end
	local ok, deck = PlayerDataStore.ValidateDeck(data.Deck, result.Owned)
	if ok then
		result.Deck = deck
	else
		for index, itemId in ipairs(Config.DefaultDeck) do
			result.Deck[index] = itemId
		end
	end
	if type(data.Beasts) == "table" then
		for id, owned in pairs(data.Beasts) do
			if owned == true and Config.Beasts[id] then
				result.Beasts[id] = true
			end
		end
	end
	if type(data.EquippedBeast) == "string" and result.Beasts[data.EquippedBeast] then
		result.EquippedBeast = data.EquippedBeast
	end
	if type(data.Trails) == "table" then
		for id, owned in pairs(data.Trails) do
			if owned == true and Config.Trails[id] then
				result.Trails[id] = true
			end
		end
	end
	local equipped = data.EquippedTrail
	-- 空文字は明示的な装備解除。未設定のパス所持者には従来の見た目を適用する。
	if type(equipped) == "string" and (equipped == "" or equipped == "Sparkle" or result.Trails[equipped]) then
		result.EquippedTrail = equipped
	end
	if type(data.BeastTradeId) == "string" then
		result.BeastTradeId = data.BeastTradeId
	end
	return result
end

-- デッキとして正しいか（数・実在・重複なし・持っている）を確かめ、正しければコピーを返す
function PlayerDataStore.ValidateDeck(list, owned)
	if type(list) ~= "table" or #list ~= Config.DeckSize then
		return false, nil
	end
	local seen = {}
	local copy = {}
	for index = 1, Config.DeckSize do
		local itemId = list[index]
		if type(itemId) ~= "string" or not Config.Items[itemId] or Config.Items[itemId].ExclusiveMap or seen[itemId] then
			return false, nil
		end
		if owned and not owned[itemId] then
			return false, nil
		end
		seen[itemId] = true
		copy[index] = itemId
	end
	return true, copy
end

---------------------------------------------------------------------
-- デイリールーレット（計算だけ）
---------------------------------------------------------------------

-- now（os.time）までにたまった権利を data に足す。data を書き換える。
-- 権利が満タンのあいだは時間をためない（回したときから次の30分を数える）。
function PlayerDataStore.AccrueRoulette(data, now)
	local rules = Config.Roulette
	if data.RouletteAt <= 0 then
		data.RouletteStock = math.max(data.RouletteStock, rules.StartStock)
		data.RouletteAt = now
		return data
	end
	if data.RouletteAt > now then
		data.RouletteAt = now -- 時計が戻ったときに、ずっと増えなくなるのを防ぐ
	end
	local gained = math.floor((now - data.RouletteAt) / rules.Interval)
	if gained > 0 then
		data.RouletteStock = math.min(rules.MaxStock, data.RouletteStock + gained)
		data.RouletteAt = data.RouletteAt + gained * rules.Interval
	end
	if data.RouletteStock >= rules.MaxStock then
		data.RouletteAt = now
	end
	return data
end

-- 画面に出す今の状態。戻り値: 回せる回数, 次の権利までの秒数（満タンなら nil）
function PlayerDataStore.RouletteView(data, now)
	PlayerDataStore.AccrueRoulette(data, now)
	if data.RouletteStock >= Config.Roulette.MaxStock then
		return data.RouletteStock, nil
	end
	return data.RouletteStock, math.max(0, data.RouletteAt + Config.Roulette.Interval - now)
end

-- 景品の番号を重みで選ぶ。roll は 0 以上 1 未満の数（省略時は乱数）
function PlayerDataStore.PickRoulettePrize(roll)
	local prizes = Config.Roulette.Prizes
	local total = 0
	for _, prize in ipairs(prizes) do
		total = total + prize.Weight
	end
	local point = (roll or math.random()) * total
	for index, prize in ipairs(prizes) do
		point = point - prize.Weight
		if point < 0 then
			return index
		end
	end
	return #prizes
end

---------------------------------------------------------------------
-- DataStore とのやりとり
---------------------------------------------------------------------

local function getStore()
	if store or storeFailed then
		return store
	end
	local ok, result = pcall(function()
		return game:GetService("DataStoreService"):GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		storeFailed = game:GetService("RunService"):IsStudio()
		warn("[PlayerDataStore] DataStore の取得に失敗: " .. tostring(result))
	end
	return store
end

local function useStudioMemory(err)
	local message = tostring(err)
	if (string.find(message, "StudioAccessToApisNotAllowed", 1, true)
		or string.find(message, "Studio access to APIs is not allowed", 1, true)
		or string.find(message, "Cannot access DataStore from studio if API services are not enabled", 1, true))
		and game:GetService("RunService"):IsStudio() then
		store = nil
		storeFailed = true
		warn("[PlayerDataStore] Studio の API アクセスが無効なため、保存せずに遊びます")
		return true
	end
	return false
end

local function keyFor(player)
	return "u_" .. tostring(player.UserId)
end

-- transform(データ) でデータを書き換えて保存する。成功したら新しいデータを返す
local function write(player, transform, memoryData)
	local wasCached = cache[player] ~= nil
	local ds = getStore()
	if ds then
		for attempt = 1, RETRIES do
			local ok, result = pcall(function()
				return ds:UpdateAsync(keyFor(player), function(old)
					local data = PlayerDataStore.Normalize(old)
					local current = cache[player]
					-- 保存データが未開始なら、ロビーで表示した起算時刻を引き継ぐ。
					if data.RouletteAt == 0 and current and current.RouletteAt > 0 then
						data.RouletteAt = current.RouletteAt
						data.RouletteStock = current.RouletteStock
					end
					if transform(data) == false then
						return nil
					end
					return data
				end)
			end)
			if ok then
				if result == nil then
					return nil
				end
				local data = PlayerDataStore.Normalize(result)
				if cache[player] or (not wasCached and not memoryData) then
					cache[player] = data
				end
				return data
			end
			if useStudioMemory(result) then
				break
			end
			warn(string.format("[PlayerDataStore] 保存に失敗（%d回目）: %s", attempt, tostring(result)))
			task.wait(attempt)
		end
	end
	if not storeFailed then
		return nil, SAVE_FAILED
	end
	-- DataStore が使えない環境ではメモリ上だけ更新する
	local current = cache[player]
	local data = PlayerDataStore.Normalize(current or memoryData)
	if transform(data) == false then
		return nil
	end
	if current or (not wasCached and not memoryData) then
		cache[player] = data
	end
	return data
end

local function update(player, transform, memoryData)
	local userId = player.UserId
	if trading[userId] then
		return nil, SAVE_FAILED
	end
	activeWrites[userId] = (activeWrites[userId] or 0) + 1
	local data, reason = write(player, transform, memoryData)
	local remaining = activeWrites[userId] - 1
	activeWrites[userId] = remaining > 0 and remaining or nil
	return data, reason
end

local pendingTrades = {}
local readOptions = Instance.new("DataStoreGetOptions")
readOptions.UseCache = false

local function journalCall(operation)
	for attempt = 1, RETRIES do
		local ok, result = pcall(function()
			local journal = game:GetService("DataStoreService"):GetDataStore("BeastTradePendingV1")
			return operation(journal)
		end)
		if ok then
			return true, result
		end
		if useStudioMemory(result) then
			break
		end
		warn("[PlayerDataStore] 交換ログの操作に失敗: " .. tostring(result))
		if attempt < RETRIES then
			task.wait(attempt)
		end
	end
	return false
end

local function tradeKey(id)
	return "trade_" .. id
end

local function setTradeStage(record, stage, isActive)
	return journalCall(function(journal)
		return journal:UpdateAsync(tradeKey(record.Id), function(current)
			if not current then
				return nil
			end
			if current.Stage == "committed" or current.Stage == "rollback" then
				return current
			end
			if stage ~= "rollback" and (os.time() >= current.ExpiresAt or (isActive and not isActive())) then
				return nil
			end
			record.Stage = stage
			return record
		end)
	end)
end

local function clearTradeIndex(player, id)
	return journalCall(function(journal)
		-- UpdateAsync の nil は更新取り消し。空の値で予約を解放する。
		journal:UpdateAsync(keyFor(player), function(current)
			if current == id then
				return false
			end
			return nil
		end)
	end)
end

local function clearTrade(record)
	-- ログ削除に失敗した場合、次の Load で再試行できるよう索引を残す。
	local removed = journalCall(function(journal)
		journal:RemoveAsync(tradeKey(record.Id))
	end)
	if not removed then
		return
	end
	for _, side in ipairs(record.Sides) do
		if clearTradeIndex(side, record.Id) and pendingTrades[side.UserId] == record.Id then
			pendingTrades[side.UserId] = nil
		end
	end
end

local function restoreTrade(record, players)
	if not getStore() then
		return false
	end
	local restored = true
	for index, side in ipairs(record.Sides) do
		if not side.Before then
			continue
		end
		local player = players and players[index]
		if not player then
			for cached in pairs(cache) do
				if cached.UserId == side.UserId then
					player = cached
					break
				end
			end
		end
		local data = write(player or side, function(fresh)
			if fresh.BeastTradeId == record.Id then
				fresh.BeastTradeId = nil
				fresh.Beasts[side.Outgoing] = side.Before.OwnedOutgoing
				fresh.Beasts[side.Incoming] = side.Before.OwnedIncoming or nil
				if side.Before.Equipped == side.Outgoing and fresh.EquippedBeast == nil then
					fresh.EquippedBeast = side.Outgoing
				end
			end
		end, {})
		restored = data ~= nil and not storeFailed and restored
	end
	return restored
end

local function recoverTrade(player)
	if not getStore() then
		return
	end
	local ok, id = journalCall(function(journal)
		return journal:GetAsync(keyFor(player), readOptions)
	end)
	if not ok then
		pendingTrades[player.UserId] = not storeFailed and true or nil
		return
	end
	pendingTrades[player.UserId] = id or nil
	if not id then
		return
	end
	local read, record = journalCall(function(journal)
		return journal:GetAsync(tradeKey(id), readOptions)
	end)
	if not read then
		return
	end
	if not record then
		if clearTradeIndex(player, id) then
			pendingTrades[player.UserId] = nil
		end
		return
	end
	if record.Stage ~= "committed" and record.Stage ~= "rollback" then
		if os.time() < record.ExpiresAt then
			return
		end
		local changed
		changed, record = setTradeStage(record, "rollback")
		if not changed or not record then
			return
		end
	end
	if record.Stage == "committed" or restoreTrade(record) then
		clearTrade(record)
	end
end

function PlayerDataStore.IsTradePending(player)
	return trading[player.UserId] or pendingTrades[player.UserId] ~= nil
end

-- 参加したときに読み込む
function PlayerDataStore.Load(player)
	loadStates[player] = "Loading"
	while trading[player.UserId] do
		task.wait()
	end
	recoverTrade(player)
	local ds = getStore()
	local data = nil
	if ds then
		for attempt = 1, RETRIES do
			local ok, result = pcall(function()
				return ds:GetAsync(keyFor(player), readOptions)
			end)
			if ok then
				data = PlayerDataStore.Normalize(result)
				break
			end
			if useStudioMemory(result) then
				break
			end
			warn(string.format("[PlayerDataStore] 読み込みに失敗（%d回目）: %s", attempt, tostring(result)))
			task.wait(attempt)
		end
	end
	local loaded = data or PlayerDataStore.Normalize(nil)
	if loadStates[player] == "Loading" then
		cache[player] = loaded
		loadStates[player] = data and "Loaded" or "Failed"
	end
	return loaded
end

function PlayerDataStore.GetLoadState(player)
	return loadStates[player] or "Loading"
end

-- 今のデータ（読み込み前なら既定値）
function PlayerDataStore.Get(player)
	local data = cache[player]
	if not data then
		data = PlayerDataStore.Normalize(nil)
		cache[player] = data
	end
	return data
end

function PlayerDataStore.Forget(player)
	loadStates[player] = nil
	cache[player] = nil
end

-- コインを足す（試合の報酬）
function PlayerDataStore.AddCoins(player, amount, won)
	return update(player, function(data)
		data.Coins = data.Coins + math.max(0, math.floor(amount))
		if won then
			data.Wins = data.Wins + 1
		end
	end)
end

-- アイテムを買う。戻り値: 成功したか, 理由（失敗時）, 新しいデータ
function PlayerDataStore.BuyItem(player, itemId)
	local def = Config.Items[itemId]
	if not def or (def.Price or 0) <= 0 then
		return false, "このアイテムは買えません", PlayerDataStore.Get(player)
	end
	local current = PlayerDataStore.Get(player)
	if current.Owned[itemId] then
		return false, "もう持っています", current
	end
	if current.Coins < def.Price then
		return false, "コインが足りません", current
	end
	local bought = false
	local data, saveError = update(player, function(fresh)
		bought = false
		if not fresh.Owned[itemId] and fresh.Coins >= def.Price then
			fresh.Coins = fresh.Coins - def.Price
			fresh.Owned[itemId] = true
			bought = true
		end
	end)
	if not data then
		return false, saveError, current
	end
	if not bought then
		return false, "コインが足りません", data
	end
	return true, nil, data
end

-- BuyItem と同じ戻り値（成功、失敗理由、データ）。
function PlayerDataStore.BuyTrail(player, id)
	local current = PlayerDataStore.Get(player)
	local def = type(id) == "string" and Config.Trails[id]
	if not def then
		return false, "このトレイルは買えません", current
	end
	local function rejection(data)
		if data.Trails[id] then
			return "もう持っています"
		elseif data.Coins < def.Price then
			return "コインが足りません"
		end
	end
	local reason = rejection(current)
	if reason then
		return false, reason, current
	end
	local data, saveError = update(player, function(fresh)
		reason = rejection(fresh)
		if reason then
			return false
		end
		fresh.Coins = fresh.Coins - def.Price
		fresh.Trails[id] = true
	end)
	return data ~= nil, saveError or reason, data or current
end

-- Sparkle のパス所持は呼び出し元が確認する。
function PlayerDataStore.SetEquippedTrail(player, id)
	local current = PlayerDataStore.Get(player)
	if type(id) ~= "string" or (id ~= "" and id ~= "Sparkle" and not current.Trails[id]) then
		return false, current
	end
	local data, saveError = update(player, function(fresh)
		if id ~= "" and id ~= "Sparkle" and not fresh.Trails[id] then
			return false
		end
		fresh.EquippedTrail = id
	end)
	return data ~= nil, data or current, saveError
end

-- レシートを確定できるのは永続保存に成功した場合だけ。
function PlayerDataStore.AddItemBox(player, purchaseId)
	if not getStore() or (purchaseId ~= nil and (type(purchaseId) ~= "string" or purchaseId == "")) then
		return false
	end
	local added
	local data = update(player, function(fresh)
		if storeFailed then
			return false
		end
		added = purchaseId == nil or not fresh.ItemBoxReceipts[purchaseId]
		if added then
			fresh.ItemBoxes += 1
			if purchaseId then
				fresh.ItemBoxReceipts[purchaseId] = true
			end
		end
	end)
	return data ~= nil, data ~= nil and added
end

-- 引き出す上限を指定すると、同時に買い足された分は残す。
function PlayerDataStore.TakeItemBoxes(player, limit, canTake)
	if not getStore() then
		return 0, false
	end
	-- UpdateAsync の応答が失われて再試行されても、同じ引き出しを繰り返さない。
	local operation = HttpService:GenerateGUID(false)
	local count = 0
	local data = update(player, function(fresh)
		if storeFailed then
			return false
		end
		local previous = fresh.ItemBoxClaims[operation]
		if previous then
			count = previous
			return
		end
		if canTake and not canTake() then
			return false
		end
		count = limit and math.min(limit, fresh.ItemBoxes) or fresh.ItemBoxes
		fresh.ItemBoxes -= count
		if count > 0 then
			fresh.ItemBoxClaims[operation] = count
		end
	end)
	if not data then
		return 0, false, operation
	end
	return count, true, operation
end

function PlayerDataStore.FinishItemBoxClaim(player, operation, delivered)
	local data = update(player, function(fresh)
		if storeFailed then
			return false
		end
		local count = fresh.ItemBoxClaims[operation]
		if not count then
			return
		end
		if not delivered then
			fresh.ItemBoxes += count
		end
		fresh.ItemBoxClaims[operation] = nil
	end, {})
	return data ~= nil
end

-- ルーレットを1回まわす。prizeIndex は先に選んだ景品の番号。
-- 戻り値: 回せたか, データ, 保存エラーの理由（失敗時）
function PlayerDataStore.SpinRoulette(player, prizeIndex, now)
	local prize = Config.Roulette.Prizes[prizeIndex]
	if not prize then
		return false, PlayerDataStore.Get(player)
	end
	now = now or os.time()
	local spun = false
	local data, saveError = update(player, function(fresh)
		spun = false
		PlayerDataStore.AccrueRoulette(fresh, now)
		if fresh.RouletteStock >= 1 then
			fresh.RouletteStock = fresh.RouletteStock - 1
			fresh.Coins = fresh.Coins + prize.Coins
			spun = true
		end
	end)
	if not data then
		return false, PlayerDataStore.Get(player), saveError
	end
	return spun, data
end

-- デッキを保存する。戻り値: 成功したか, 新しいデータ
function PlayerDataStore.SetDeck(player, list)
	local ok, deck = PlayerDataStore.ValidateDeck(list, PlayerDataStore.Get(player).Owned)
	if not ok then
		return false, PlayerDataStore.Get(player)
	end
	local data = update(player, function(fresh)
		local stillOk, freshDeck = PlayerDataStore.ValidateDeck(deck, fresh.Owned)
		if stillOk then
			fresh.Deck = freshDeck
		end
	end)
	return data ~= nil, data or PlayerDataStore.Get(player)
end

-- roll は [0, 1) の値。Config の重みを順に並べて抽選する。
function PlayerDataStore.PickBeast(roll)
	local total = 0
	for _, id in ipairs(Config.BeastOrder) do
		total += Config.Beasts[id].Weight
	end
	local upper = 0
	for _, id in ipairs(Config.BeastOrder) do
		upper += Config.Beasts[id].Weight
		if roll < upper / total then
			return id
		end
	end
end

function PlayerDataStore.DrawBeast(player)
	local current = PlayerDataStore.Get(player)
	if current.Coins < Config.BeastDrawCost then
		return nil, "コインが足りません", current
	end

	-- UpdateAsync が同じ処理を再実行しても抽選結果は固定する。
	local id = PlayerDataStore.PickBeast(math.random())
	local result
	local data, saveError = update(player, function(fresh)
		result = nil
		if fresh.Coins >= Config.BeastDrawCost then
			local duplicate = fresh.Beasts[id] == true
			fresh.Coins -= Config.BeastDrawCost
			if duplicate then
				fresh.Coins += Config.BeastDuplicateRefund
			end
			fresh.Beasts[id] = true
			result = { Id = id, Duplicate = duplicate }
		end
	end)
	if not data then
		return nil, saveError, current
	end
	return result, result == nil and "コインが足りません" or nil, data
end

-- 管理者から付与された召喚獣を所持品に加える。
function PlayerDataStore.GrantBeast(player, id)
	if type(id) ~= "string" or not Config.Beasts[id] then
		return false, "召喚獣を確認してください"
	end
	local duplicate
	local data, saveError = update(player, function(fresh)
		duplicate = fresh.Beasts[id] == true
		fresh.Beasts[id] = true
	end)
	if not data then
		return false, saveError
	end
	if duplicate then
		return false, "この召喚獣はすでに所持しています"
	end
	return true
end

function PlayerDataStore.SetEquippedBeast(player, id)
	local current = PlayerDataStore.Get(player)
	local unequip = id == ""
	if type(id) ~= "string" or (not unequip and not current.Beasts[id]) then
		return false, current
	end
	local equipped = false
	local data, saveError = update(player, function(fresh)
		equipped = unequip or fresh.Beasts[id] == true
		if unequip then
			fresh.EquippedBeast = nil
		elseif equipped then
			fresh.EquippedBeast = id
		end
	end)
	if not data then
		return false, current, saveError
	end
	return equipped, data
end

local DUPLICATE_BEAST = "受け取る召喚獣を既に所持しているため交換できません"

function PlayerDataStore.TradeBeasts(playerA, idA, playerB, idB, isActive)
	local userA, userB = playerA.UserId, playerB.UserId
	if userA == userB or idA == idB or type(idA) ~= "string" or type(idB) ~= "string"
		or not Config.Beasts[idA] or not Config.Beasts[idB] then
		return false, "交換する相手と召喚獣を確認してください"
	end
	if PlayerDataStore.IsTradePending(playerA) or PlayerDataStore.IsTradePending(playerB)
		or activeWrites[userA] or activeWrites[userB] then
		return false, "データの保存または交換の復元中です"
	end
	trading[userA], trading[userB] = true, true

	local players = { playerA, playerB }
	local record = {
		Id = HttpService:GenerateGUID(false),
		Stage = "preparing",
		ExpiresAt = os.time() + 120,
		Sides = {
			{ UserId = userA, Outgoing = idA, Incoming = idB },
			{ UserId = userB, Outgoing = idB, Incoming = idA },
		},
	}
	local missing = "交換に出した召喚獣を所持していません"

	local function snapshot(side, data)
		if data.Beasts[side.Incoming] then
			return DUPLICATE_BEAST
		end
		if not data.Beasts[side.Outgoing] then
			return missing
		end
		side.Before = {
			OwnedOutgoing = true,
			OwnedIncoming = false,
			Equipped = data.EquippedBeast,
		}
	end

	local ds = getStore()
	local function exchange(side, player)
		local rejected
		local data, reason = write(player, function(fresh)
			if fresh.BeastTradeId == record.Id then
				return
			end
			if ds and (os.time() >= record.ExpiresAt or (isActive and not isActive())) then
				return false
			end
			if fresh.Beasts[side.Incoming] then
				rejected = DUPLICATE_BEAST
				return false
			end
			if not fresh.Beasts[side.Outgoing] then
				rejected = missing
				return false
			end
			if fresh.EquippedBeast ~= side.Before.Equipped then
				rejected = "装備が変更されました。もう一度お試しください"
				return false
			end
			if fresh.EquippedBeast == side.Outgoing then
				fresh.EquippedBeast = nil
			end
			fresh.Beasts[side.Outgoing] = nil
			fresh.Beasts[side.Incoming] = true
			fresh.BeastTradeId = record.Id
		end)
		return data, reason or rejected
	end

	local journalStarted = false
	local function saveTrade()
		if not ds then
			if not game:GetService("RunService"):IsStudio() then
				return false, SAVE_FAILED
			end
			for index, side in ipairs(record.Sides) do
				local reason = snapshot(side, PlayerDataStore.Get(players[index]))
				if reason then
					return false, reason
				end
			end
			if isActive and not isActive() then
				return false, SAVE_FAILED
			end
			for index, side in ipairs(record.Sides) do
				exchange(side, players[index])
			end
			return true
		end

		journalStarted = true
		local created = journalCall(function(journal)
			journal:SetAsync(tradeKey(record.Id), record)
		end)
		if not created then
			return false, SAVE_FAILED
		end
		for _, side in ipairs(record.Sides) do
			local ok, id = journalCall(function(journal)
				return journal:UpdateAsync(keyFor(side), function(current)
					if os.time() >= record.ExpiresAt or (current and current ~= record.Id) then
						return nil
					end
					return record.Id
				end)
			end)
			if not ok or id == record.Id then
				pendingTrades[side.UserId] = record.Id
			end
			if not ok or id ~= record.Id then
				return false, "未完了の交換があるため交換できません"
			end
		end
		for _, side in ipairs(record.Sides) do
			local ok, fresh = pcall(ds.GetAsync, ds, keyFor(side), readOptions)
			if not ok then
				return false, SAVE_FAILED
			end
			local reason = snapshot(side, PlayerDataStore.Normalize(fresh))
			if reason then
				return false, reason
			end
		end
		local prepared, logged = setTradeStage(record, "applying")
		if not prepared or not logged or logged.Stage ~= "applying" then
			return false, SAVE_FAILED
		end
		for index, side in ipairs(record.Sides) do
			local saved, reason = exchange(side, players[index])
			if not saved or storeFailed then
				return false, reason or SAVE_FAILED
			end
		end
		if isActive and not isActive() then
			return false, SAVE_FAILED
		end
		return true
	end

	local saved, reason = saveTrade()
	if journalStarted then
		local ok, logged = setTradeStage(record, saved and "committed" or "rollback", isActive)
		if ok and not logged and saved then
			ok, logged = setTradeStage(record, "rollback")
		end
		saved = ok and logged ~= nil and logged.Stage == "committed"
		if saved or (ok and logged and logged.Stage == "rollback" and restoreTrade(logged, players)) then
			clearTrade(logged)
		end
	end
	trading[userA], trading[userB] = nil, nil
	return saved, not saved and (reason or SAVE_FAILED) or nil
end

return PlayerDataStore
