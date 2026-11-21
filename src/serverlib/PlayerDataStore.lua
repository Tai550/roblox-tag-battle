-- PlayerDataStore: プレイヤーの保存データ（コイン・持っているアイテム・デッキ）
-- ロビーと試合の両方のサーバーから使う。DataStore への書き込みは必ず UpdateAsync で
-- 「その場で読み直して足す」形にし、ロビーと試合で同時に書いても上書きし合わないようにする。
--
-- 保存形式（キー "u_<UserId>"）:
--   { Coins = 数, Owned = { [アイテムId] = true }, Deck = { アイテムId, ... }, Wins = 数,
--     Beasts = { [召喚獣Id] = true }, EquippedBeast = Id,
--     RouletteStock = ルーレットを回せる回数, RouletteAt = 権利を数え始めた時刻（os.time。0 は未開始） }
--
-- DataStore が使えない環境では、
-- メモリ上のデータで遊べるようにする（保存はされない）。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local PlayerDataStore = {}

local STORE_NAME = "PlayerData_v1"
local RETRIES = 3
local SAVE_FAILED = "データを保存できませんでした。もう一度お試しください"

local store = nil        -- DataStore（初めて使うときに取得する）
local storeFailed = false
local cache = {}         -- [Player] = データ

---------------------------------------------------------------------
-- 計算だけの関数（テストからも呼べる）
---------------------------------------------------------------------

-- 壊れたデータや古い形式を、正しい形にそろえて返す
function PlayerDataStore.Normalize(raw)
	local data = type(raw) == "table" and raw or {}
	local result = {
		Coins = math.max(0, math.floor(tonumber(data.Coins) or 0)),
		Owned = {},
		Deck = {},
		Beasts = {},
		Wins = math.max(0, math.floor(tonumber(data.Wins) or 0)),
		RouletteStock = math.clamp(math.floor(tonumber(data.RouletteStock) or 0), 0, Config.Roulette.MaxStock),
		RouletteAt = math.max(0, math.floor(tonumber(data.RouletteAt) or 0)),
	}
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
		storeFailed = true
		warn("[PlayerDataStore] DataStore が使えないため、保存せずに遊びます: " .. tostring(result))
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
local function update(player, transform)
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
					transform(data)
					return data
				end)
			end)
			if ok then
				local data = PlayerDataStore.Normalize(result)
				cache[player] = data
				return data
			end
			if useStudioMemory(result) then
				break
			end
			warn(string.format("[PlayerDataStore] 保存に失敗（%d回目）: %s", attempt, tostring(result)))
			task.wait(attempt)
		end
		if not storeFailed then
			return nil, SAVE_FAILED
		end
	end
	-- DataStore が使えない環境ではメモリ上だけ更新する
	local data = PlayerDataStore.Get(player)
	transform(data)
	return data
end

-- 参加したときに読み込む
function PlayerDataStore.Load(player)
	local ds = getStore()
	local data = nil
	if ds then
		for attempt = 1, RETRIES do
			local ok, result = pcall(function()
				return ds:GetAsync(keyFor(player))
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
	cache[player] = data or PlayerDataStore.Normalize(nil)
	return cache[player]
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

function PlayerDataStore.SetEquippedBeast(player, id)
	local current = PlayerDataStore.Get(player)
	if type(id) ~= "string" or not current.Beasts[id] then
		return false, current
	end
	local equipped = false
	local data, saveError = update(player, function(fresh)
		equipped = fresh.Beasts[id] == true
		if equipped then
			fresh.EquippedBeast = id
		end
	end)
	if not data then
		return false, current, saveError
	end
	return equipped, data
end

return PlayerDataStore
