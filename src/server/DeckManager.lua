-- DeckManager: デッキ構築の管理（検証はすべてサーバー）
--
-- プレイヤーは全アイテムの中から Config.DeckSize 個を選んでデッキにする。
-- フィールドのボックスを拾うと、自分のデッキの中からランダムで1つ手に入る。
-- クライアントから届く DeckSelect の中身は信用せず、ここで検証してから採用する。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local DeckManager = {}

local decks = {} -- [Player] = { アイテム Id のリスト }

---------------------------------------------------------------------
-- 検証（計算だけの関数。テストからも呼べる）
---------------------------------------------------------------------

-- デッキとして正しいかどうかを検証し、正しければ正規化したコピーを返す。
-- 条件: 配列であること、数が Config.DeckSize と一致すること、
--       すべて実在するアイテム Id であること、重複がないこと
function DeckManager.ValidateDeck(list)
	if type(list) ~= "table" then
		return false, nil
	end
	if #list ~= Config.DeckSize then
		return false, nil
	end
	local seen = {}
	local copy = {}
	for index = 1, Config.DeckSize do
		local itemId = list[index]
		if type(itemId) ~= "string" or not Config.Items[itemId] then
			return false, nil
		end
		if seen[itemId] then
			return false, nil
		end
		seen[itemId] = true
		copy[index] = itemId
	end
	return true, copy
end

-- デッキの中からランダムで1つ選ぶ（計算だけの関数）
function DeckManager.PickRandomFromDeck(deck)
	if not deck or #deck == 0 then
		return nil
	end
	return deck[math.random(1, #deck)]
end

---------------------------------------------------------------------
-- デッキの取得・設定
---------------------------------------------------------------------

local function defaultDeck()
	local copy = {}
	for index, itemId in ipairs(Config.DefaultDeck) do
		copy[index] = itemId
	end
	return copy
end

-- そのプレイヤーの今のデッキを返す（選んでいなければ既定のデッキ）
function DeckManager.GetDeck(player)
	local deck = decks[player]
	if not deck then
		deck = defaultDeck()
		decks[player] = deck
	end
	local copy = {}
	for index, itemId in ipairs(deck) do
		copy[index] = itemId
	end
	return copy
end

local function sendDeckUpdate(player)
	if player and player.Parent then
		Remotes.DeckUpdate:FireClient(player, { Deck = DeckManager.GetDeck(player) })
	end
end

-- デッキを設定する。検証に通らなければ今のデッキのまま（戻り値 false）
function DeckManager.SetDeck(player, list)
	local ok, copy = DeckManager.ValidateDeck(list)
	if not ok then
		return false
	end
	decks[player] = copy
	sendDeckUpdate(player)
	Remotes.NotifyPlayer(player, "デッキを変更した！")
	return true
end

-- ボックスを拾ったとき用：そのプレイヤーのデッキからランダムで1つ選ぶ
function DeckManager.PickFromDeck(player)
	return DeckManager.PickRandomFromDeck(DeckManager.GetDeck(player))
end

---------------------------------------------------------------------
-- 初期化
---------------------------------------------------------------------

local function onDeckSelect(player, list)
	-- 配列でない引数は「今のデッキを送って」という合図として扱う
	if type(list) ~= "table" then
		sendDeckUpdate(player)
		return
	end
	DeckManager.SetDeck(player, list)
end

function DeckManager.Init()
	Remotes.DeckSelect.OnServerEvent:Connect(onDeckSelect)

	Players.PlayerAdded:Connect(function(player)
		decks[player] = defaultDeck()
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		decks[player] = defaultDeck()
	end
	Players.PlayerRemoving:Connect(function(player)
		decks[player] = nil
	end)
end

return DeckManager
