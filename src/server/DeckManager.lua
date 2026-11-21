-- DeckManager: 試合中のデッキ（読み取り専用）
--
-- デッキはロビーで組み、保存データ（PlayerDataStore）に入っている。
-- 試合サーバーでは変更を受け付けず、ボックスを拾ったときの抽選にだけ使う。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local PlayerDataStore = require(script.Parent:WaitForChild("PlayerDataStore"))

local DeckManager = {}

---------------------------------------------------------------------
-- 計算だけの関数（テストからも呼べる）
---------------------------------------------------------------------

-- デッキとして正しいか（数・実在・重複なし）。持っているかどうかはロビーで確かめる
function DeckManager.ValidateDeck(list)
	return PlayerDataStore.ValidateDeck(list, nil)
end

-- デッキの中からランダムで1つ選ぶ
function DeckManager.PickRandomFromDeck(deck)
	if not deck or #deck == 0 then
		return nil
	end
	return deck[math.random(1, #deck)]
end

---------------------------------------------------------------------
-- デッキの取得
---------------------------------------------------------------------

-- そのプレイヤーのデッキ（コピー）を返す
function DeckManager.GetDeck(player)
	local deck = nil
	if not (type(player) == "table" and player.IsBot == true) then -- ボットは保存データを持たないので最初のデッキ
		deck = PlayerDataStore.Get(player).Deck
	end
	local ok, copy = DeckManager.ValidateDeck(deck)
	if ok then
		return copy
	end
	local fallback = {}
	for index, itemId in ipairs(Config.DefaultDeck) do
		fallback[index] = itemId
	end
	return fallback
end

-- ボックスを拾ったとき用：そのプレイヤーのデッキからランダムで1つ選ぶ
function DeckManager.PickFromDeck(player)
	return DeckManager.PickRandomFromDeck(DeckManager.GetDeck(player))
end

-- ボットを消すときに呼ばれる。試合サーバーではデッキを覚えていないので何もしない
function DeckManager.Release(_player) end

function DeckManager.Init(onLoaded)
	local function load(player)
		PlayerDataStore.Load(player)
		if player.Parent ~= Players then
			PlayerDataStore.Forget(player)
		elseif onLoaded then
			onLoaded(player)
		end
	end
	Players.PlayerAdded:Connect(load)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		PlayerDataStore.Forget(player)
	end)
end

return DeckManager
