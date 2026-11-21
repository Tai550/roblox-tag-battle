-- PlayerDataStore: プレイヤーの保存データ（コイン・持っているアイテム・デッキ）
-- ロビーと試合の両方のサーバーから使う。DataStore への書き込みは必ず UpdateAsync で
-- 「その場で読み直して足す」形にし、ロビーと試合で同時に書いても上書きし合わないようにする。
--
-- 保存形式（キー "u_<UserId>"）:
--   { Coins = 数, Owned = { [アイテムId] = true }, Deck = { アイテムId, ... }, Wins = 数 }
--
-- Studio で「API サービスへのアクセス」が無効なときや通信に失敗したときは、
-- メモリ上のデータで遊べるようにする（保存はされない）。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local PlayerDataStore = {}

local STORE_NAME = "PlayerData_v1"
local RETRIES = 3

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
		Wins = math.max(0, math.floor(tonumber(data.Wins) or 0)),
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
		if type(itemId) ~= "string" or not Config.Items[itemId] or seen[itemId] then
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
					transform(data)
					return data
				end)
			end)
			if ok then
				local data = PlayerDataStore.Normalize(result)
				cache[player] = data
				return data
			end
			warn(string.format("[PlayerDataStore] 保存に失敗（%d回目）: %s", attempt, tostring(result)))
			task.wait(attempt)
		end
	end
	-- 保存できないときはメモリ上だけ更新する
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
	local data = update(player, function(fresh)
		bought = false
		if not fresh.Owned[itemId] and fresh.Coins >= def.Price then
			fresh.Coins = fresh.Coins - def.Price
			fresh.Owned[itemId] = true
			bought = true
		end
	end)
	if not bought then
		return false, "コインが足りません", data
	end
	return true, nil, data
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
	return true, data
end

return PlayerDataStore
